///
module modbus.protocol;

import std.bitmanip : BitArray;
version (modbus_verbose)
    public import std.experimental.logger;

public import modbus.exception;

import modbus.func;

package enum MAX_WRITE_BUFFER = 260;

///
class Modbus
{
protected:
    Backend be;


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
     +/
    this(Backend be)
    {
        if (be is null)
            throw modbusException("backend is null");
        this.be = be;
    }

    /++ Write to serial port

        Params:
            dev = modbus device address (number)
            fnc = function number
            args = writed data in native endian
     +/
    const(void)[] write(Args...)(ulong dev, ubyte fnc, Args args)
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
                    foreach (v; val.tupleof) _append(v);
                else static if (isNumeric!T) be.append(val);
                else static assert(0, "unsupported type " ~ T.stringof);
            }
        }

        foreach (arg; args) _append(arg);

        be.send();

        return be.tempBuffer;
    }

    /++ Read from serial port

        Params:
            dev = modbus device address (number)
            fnc = function number
            bytes = expected response length in bytes

        Returns:
            result in big endian
     +/
    const(void)[] read(ulong dev, ubyte fnc, size_t bytes)
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

    /++ Write and read to modbus

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
        auto tmp = write(dev, fnc, args);
        void[MAX_WRITE_BUFFER] writed = void;
        writed[0..tmp.length] = tmp[];

        try return read(dev, fnc, bytes);
        catch (ModbusDevException e)
        {
            e.writed = writed[0..tmp.length];
            throw e;
        }
    }

    /// function number 0x1 (1)
    const(BitArray) readCoils(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        return const(BitArray)(cast(void[])request(dev, 1, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    /// function number 0x2 (2)
    const(BitArray) readDiscreteInputs(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        return const(BitArray)(cast(void[])request(dev, 2, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    private alias be2na = bigEndianToNativeArr;

    /++ function number 0x3 (3)
        Returns: data in native endian
     +/ 
    const(ushort)[] readHoldingRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        return be2na(cast(ushort[])request(dev, 3, 1+cnt*2, start, cnt)[1..$]);
    }

    /++ function number 0x4 (4)
        Returns: data in native endian
     +/ 
    const(ushort)[] readInputRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        return be2na(cast(ushort[])request(dev, 4, 1+cnt*2, start, cnt)[1..$]);
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