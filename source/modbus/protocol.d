///
module modbus.protocol;

import std.bitmanip : BitArray;
debug (modbus_verbose)
    import std.experimental.logger;

public import modbus.exception;

import modbus.func;

///
class Modbus
{
protected:
    Backend be;

public:

    static interface Backend
    {
        /// start building message
        void start(ubyte dev, ubyte func);

        /// append data to message buffer
        void append(byte);
        /// ditto
        void append(ubyte);
        /// ditto
        void append(short);
        /// ditto
        void append(ushort);
        /// ditto
        void append(int);
        /// ditto
        void append(uint);
        /// ditto
        void append(long);
        /// ditto
        void append(ulong);
        /// ditto
        void append(float);
        /// ditto
        void append(double);
        /// ditto
        void append(const(void)[]);

        ///
        bool messageComplite() const @property;

        /// temp message buffer
        const(void)[] tempBuffer() const @property;

        /// send and clear temp message
        void send();

        /// Readed modbus response
        static struct Response
        {
            /// device number
            ubyte dev;
            /// function number
            ubyte fnc;

            /// data without any changes
            const(void)[] data;
        }

        /// read data to temp message buffer
        Response read(size_t expectedBytes);
    }

    invariant
    {
        if (be !is null)
            assert(be.messageComplite);
    }

    ///
    this(Backend be)
    {
        if (be is null)
            throw modbusException("backend is null");
        this.be = be;
    }

    ///
    void write(Args...)(ubyte dev, ubyte func, Args args)
    {
        import std.range : ElementType;
        import std.traits : isArray, isNumeric, Unqual;

        be.start(dev, func);

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
    }

    /// result in big endian
    const(void)[] read(ubyte dev, ubyte fnc, size_t bytes)
    {
        auto res = be.read(bytes);

        debug (modbus_verbose)
            if (res.dev != dev)
                .warningf("receive from unexpected device %d (expect %d)",
                                res.dev, dev);
        
        if (res.fnc != fnc)
            throw functionErrorException(dev, fnc, res.fnc, (cast(ubyte[])res.data)[0]);

        if (res.data.length != bytes)
            throw readDataLengthException(dev, fnc, bytes, res.data.length);

        return res.data;
    }

    /++ Write and read to modbus

        Params:
        dev - slave device number
        fnc - called function number
        bytes - expected bytes for reading
        args - sending data
     +/
    const(void)[] request(Args...)(ubyte dev, ubyte fnc, size_t bytes, Args args)
    {
        this.write(dev, fnc, args);
        return read(dev, fnc, bytes);
    }

    /// function number 0x1 (1)
    const(BitArray) readCoils(ubyte dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        return const(BitArray)(cast(void[])request(dev, 1, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    /// function number 0x2 (2)
    const(BitArray) readDiscreteInputs(ubyte dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        return const(BitArray)(cast(void[])request(dev, 2, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    /++ function number 0x3 (3)
        Returns: data in native endian
     +/ 
    const(ushort)[] readHoldingRegisters(ubyte dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        return bigEndianToNativeArr(cast(ushort[])request(dev, 3, 1+cnt*2, start, cnt)[1..$]);
    }

    /++ function number 0x4 (4)
        Returns: data in native endian
     +/ 
    const(ushort)[] readInputRegisters(ubyte dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        return bigEndianToNativeArr(cast(ushort[])request(dev, 4, 1+cnt*2, start, cnt)[1..$]);
    }

    /// function number 0x5 (5)
    void writeSingleCoil(ubyte dev, ushort addr, bool val)
    { request(dev, 5, 4, addr, cast(ushort)(val ? 0xff00 : 0x0000)); }

    /// function number 0x6 (6)
    void writeSingleRegister(ubyte dev, ushort addr, ushort value)
    { request(dev, 6, 4, addr, value); }

    /// function number 0x10 (16)
    void writeMultipleRegisters(ubyte dev, ushort addr, ushort[] values)
    {
        if (values.length >= 125) throw modbusException("very big count");
        request(dev, 16, 4, addr, cast(ushort)values.length,
                    cast(byte)(values.length*2), values);
    }
}