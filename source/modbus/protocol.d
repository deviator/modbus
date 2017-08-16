///
module modbus.protocol;

import std.bitmanip : BitArray;
version (modbus_verbose)
    import std.experimental.logger;

public import modbus.exception;

import modbus.func;

package enum MAX_WRITE_BUFFER = 260;

///
class Modbus
{
protected:
    Backend be;

    int fiber_mutex;
    static struct FSync
    {
        int* mutex;
        this(Modbus m)
        {
            mutex = &(m.fiber_mutex);
            while (*mutex != 0) m.yield();
            *mutex = 1;
        }

        ~this() { *mutex = 0; }
    }

    void yield()
    {
        import core.thread;
        if (yieldFunc != null) yieldFunc();
        else if (Fiber.getThis !is null)
            Fiber.yield();
        else
        {
            // unspecific state, if vars must
            // changes it can be not changed
            version (modbus_verbose)
                .warning("Thread.yield can block execution");
            Thread.yield();
        }
    }

    void delegate() yieldFunc;

public:

    ///
    static interface Backend
    {
        /// start building message
        void start(ulong dev, ubyte func);

        /// append data to message buffer
        void append(byte);
        /// ditto
        void append(short);
        /// ditto
        void append(int);
        /// ditto
        void append(long);
        /// ditto
        void append(float);
        /// ditto
        void append(double);
        /// ditto
        void append(const(void)[]);

        /// temp message buffer
        const(void)[] tempBuffer() const @property;

        /// send data
        void send();

        /// Readed modbus response
        static struct Response
        {
            /// device number
            ulong dev;
            /// function number
            ubyte fnc;

            /// data without any changes
            const(void)[] data;
        }

        /++ Read data to temp message buffer
            Params:
            expectedBytes = count of bytes in data section of message,
                            exclude device address, function number, CRC and etc
         +/
        Response read(size_t expectedBytes);
    }

    /++ 
        Params:
            be = Backend
            yieldFunc = needs if used in fiber-based code (vibe for example)
     +/
    this(Backend be, void delegate() yieldFunc=null)
    {
        if (be is null)
            throw modbusException("backend is null");
        this.be = be;
        this.yieldFunc = yieldFunc;
    }

    // fiber unsafe write
    private const(void)[] fusWrite(Args...)(ulong dev, ubyte fnc, Args args)
    {
        import std.range : ElementType;
        import std.traits : isArray, isNumeric, Unqual;

        be.start(dev, fnc);

        void _append(T)(T val)
        {
            static if (isArray!T)
            {
                static if (is(Unqual!(ElementType!T) == void))
                    be.append(val);
                else foreach (e; val) _append(e);
            }
            else
            {
                static if (is(T == struct))
                    foreach (name; __traits(allMembers, T))
                        _append(__traits(getMember, val, name));
                else static if (isNumeric!T) be.append(val);
                else static assert(0, "unsupported type " ~ T.stringof);
            }
        }

        foreach (arg; args) _append(arg);

        be.send();

        return be.tempBuffer;
    }

    /++ Write to serial port

        fiber-safe

        Params:
            dev = modbus device address (number)
            fnc = function number
            args = writed data in native endian
     +/
    void write(Args...)(ulong dev, ubyte fnc, Args args)
    {
        auto fsync = FSync(this);
        fusWrite(dev, fnc, args);
    }

    ///
    void flush()
    {
        import serialport;
        try
        {
            auto res = be.read(240);
            version (modbus_verbose)
                .info("flush ", cast(ubyte[])(res.data));
        }
        catch (TimeoutException e)
            version (modbus_verbose)
                .trace("flust timeout");
    }

    // fiber unsafe read
    private const(void)[] fusRead(ulong dev, ubyte fnc, size_t bytes)
    {
        try
        {
            auto res = be.read(bytes);

            version (modbus_verbose)
                if (res.dev != dev)
                    .warningf("receive from unexpected device %d (expect %d)",
                                    res.dev, dev);
            
            if (res.fnc != fnc)
                throw functionErrorException(dev, fnc, res.fnc, (cast(ubyte[])res.data)[0]);

            if (res.data.length != bytes)
                throw  readDataLengthException(dev, fnc, bytes, res.data.length);

            return res.data;
        }
        catch (ModbusDevException e)
        {
            e.readed = be.tempBuffer;
            throw e;
        }
    }

    /++ Read from serial port

        fiber-safe

        Params:
            dev = modbus device address (number)
            fnc = function number
            bytes = expected response length in bytes

        Returns:
            result in big endian
     +/
    const(void)[] read(ulong dev, ubyte fnc, size_t bytes)
    {
        auto fsync = FSync(this);
        return fusRead(dev, fnc, bytes);
    }

    // fiber unsafe request
    private const(void)[] fusRequest(Args...)(ulong dev, ubyte fnc, size_t bytes, Args args)
    {
        auto tmp = fusWrite(dev, fnc, args);
        void[MAX_WRITE_BUFFER] writed = void;
        writed[0..tmp.length] = tmp[];

        try return fusRead(dev, fnc, bytes);
        catch (ModbusDevException e)
        {
            e.writed = writed[0..tmp.length];
            throw e;
        }
    }

    /++ Write and read to modbus

        fiber-safe

        Params:
            dev = slave device number
            fnc = called function number
            bytes = expected bytes for reading
            args = sending data
        Returns:
            result in big endian
     +/
    const(void)[] request(Args...)(ulong dev, ubyte fnc, size_t bytes, Args args)
    {
        auto fsync = FSync(this);
        return fusRequest(dev, fnc, bytes, args);
    }

    /// function number 0x1 (1)
    const(BitArray) readCoils(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        auto fsync = FSync(this);
        return const(BitArray)(cast(void[])fusRequest(dev, 1, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    /// function number 0x2 (2)
    const(BitArray) readDiscreteInputs(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        auto fsync = FSync(this);
        return const(BitArray)(cast(void[])fusRequest(dev, 2, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    /++ function number 0x3 (3)
        Returns: data in native endian
     +/ 
    const(ushort)[] readHoldingRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        auto fsync = FSync(this);
        return bigEndianToNativeArr(cast(ushort[])fusRequest(dev, 3, 1+cnt*2, start, cnt)[1..$]);
    }

    /++ function number 0x4 (4)
        Returns: data in native endian
     +/ 
    const(ushort)[] readInputRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        auto fsync = FSync(this);
        return bigEndianToNativeArr(cast(ushort[])fusRequest(dev, 4, 1+cnt*2, start, cnt)[1..$]);
    }

    /// function number 0x5 (5)
    void writeSingleCoil(ulong dev, ushort addr, bool val)
    { request(dev, 5, 4, addr, cast(ushort)(val ? 0xff00 : 0x0000)); }

    /// function number 0x6 (6)
    void writeSingleRegister(ulong dev, ushort addr, ushort value)
    { request(dev, 6, 4, addr, value); }

    /// function number 0x10 (16)
    void writeMultipleRegisters(ulong dev, ushort addr, const(ushort)[] values)
    {
        if (values.length >= 125) throw modbusException("very big count");
        request(dev, 16, 4, addr, cast(ushort)values.length,
                    cast(byte)(values.length*2), values);
    }
}