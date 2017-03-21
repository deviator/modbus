module modbus.protocol;

import std.exception : enforce;
import std.string;
import std.bitmanip;
import std.traits : isArray, Unqual, isNumeric;
import std.range : ElementType;
import std.experimental.logger;

public import modbus.exception;

import modbus.func;

class Modbus
{
protected:
    Backend be;

public:

    static interface Backend
    {
        void start(ubyte dev, ubyte func);

        void append(byte);
        void append(ubyte);
        void append(short);
        void append(ushort);
        void append(int);
        void append(uint);
        void append(long);
        void append(ulong);
        void append(float);
        void append(double);
        void append(const(void)[]);

        bool messageComplite() const @property;
        const(void)[] tempBuffer() const @property;

        void send();

        static struct Response
        {
            ubyte dev, fnc;
            const(void)[] data;
        }

        Response read(size_t expectedBytes);
    }

    invariant
    {
        assert(be.messageComplite);
    }

    this(Backend be) { this.be = enforce(be, "backend is null"); }

    bool needCheckCRC = true;

    void write(Args...)(ubyte dev, ubyte func, Args args)
    {
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

    // result in big endian
    const(void)[] read(size_t bytes, ubyte dev, ubyte fnc)
    {
        auto res = be.read(bytes);

        if (res.dev != dev)
            .warningf("receive from unexpected device %d (expect %d)",
                             res.dev, dev);

        enforce(res.fnc == fnc,
            new FunctionErrorException(dev, fnc, res.fnc, (cast(ubyte[])res.data)[0]));

        enforce(res.data.length == bytes,
            new ReadDataLengthException(dev, fnc, bytes, res.data.length));

        return res.data;
    }

    const(BitArray) readCoils(ubyte dev, ushort start, ushort cnt)
    {
        enforce(cnt <= 2000, "very big count");
        this.write(dev, 1, start, cnt);

        return const(BitArray)(cast(void[])this.read(1+(cnt+7)/8, dev, 1)[1..$], cnt);
    }

    const(BitArray) readDiscreteInputs(ubyte dev, ushort start, ushort cnt)
    {
        enforce(cnt <= 2000, "very big count");
        this.write(dev, 2, start, cnt);
        return const(BitArray)(cast(void[])this.read(1+(cnt+7)/8, dev, 2)[1..$], cnt);
    }

    ushort[] readHoldingRegisters(ubyte dev, ushort start, ushort cnt)
    {
        enforce(cnt <= 125, "very big count");
        this.write(dev, 3, start, cnt);
        auto res = this.read(1+cnt*2, dev, 3);
        return bigEndianToNativeArr(cast(ushort[])res[1..$]);
    }

    ushort[] readInputRegisters(ubyte dev, ushort start, ushort cnt)
    {
        enforce(cnt <= 125, "very big count");
        this.write(dev, 4, start, cnt);
        auto res = this.read(1+cnt*2, dev, 4);
        return bigEndianToNativeArr(cast(ushort[])res[1..$]);
    }

    void writeSingleCoil(ubyte dev, ushort addr, bool val)
    {
        this.write(dev, 5, addr, cast(ushort)(val ? 0xff00: 0x0000));
        this.read(4, dev, 5);
    }

    void writeSingleRegister(ubyte dev, ushort addr, ushort value)
    {
        this.write(dev, 6, addr, value);
        this.read(4, dev, 6);
    }

    void writeMultipleRegisters(ubyte dev, ushort addr, ushort[] values)
    {
        enforce(values.length <= 125, "very big count");
        this.write(dev, 16, addr, cast(ushort)values.length,
                    cast(byte)(values.length*2), values);
        this.read(4, dev, 16);
    }
}
