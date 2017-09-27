///
module modbus.backend.specrules;

version (modbus_verbose)
    import std.experimental.logger;

///
interface SpecRules
{
pure @nogc:
    ///
    @property size_t deviceTypeSize();

    ///
    const(void)[] packDF(ulong dev, ubyte fnc);
    ///
    int peekDF(const(void)[] buf, ref ulong dev, ref ubyte fnc);

    ///
    const(void)[] pack(const(void)[]);
    ///
    const(void)[] packT(T)(T value)
    { return pack((cast(void*)&value)[0..T.sizeof]); }

    ///
    const(void)[] unpack(const(void)[] data);
    ///
    final T unpackT(T)(const(void)[] data)
    { return (cast(T[])unpack(data))[0]; }
}

///
class BasicSpecRules : SpecRules
{
    protected ubyte[16] buffer;

    private const(void)[] typedPack(T)(T v) @nogc
    {
        import std.bitmanip : write;

        static if (T.sizeof <= ushort.sizeof)
            buffer[].write(v, 0);
        else
        {
            size_t i;
            foreach (part; cast(ushort[])((cast(void[T.sizeof])(cast(T[1])[v]))[]))
                buffer[].write(part, &i);
        }

        return buffer[0..T.sizeof];
    }

    private const(void)[] typedUnpack(T)(const(void)[] data) @nogc 
    {
        import std.bitmanip : read;
        import std.algorithm : min;
        import std.range : chunks, enumerate;

        static if (T.sizeof == ubyte.sizeof) return data;
        else
        {
            enum us = ushort.sizeof;
            foreach (i, s; (cast(const(ubyte)[])data).chunks(us).enumerate)
            {
                auto tmp = s.read!ushort;
                buffer[i*us..(i+1)*us] = (cast(ubyte*)&tmp)[0..us];
            }
            return buffer[0..T.sizeof];
        }
    }

    import std.meta : AliasSeq;
    alias Types = AliasSeq!(byte,short,int,long);

public pure override @nogc:
    @property size_t deviceTypeSize() { return 1; }

    const(void)[] packDF(ulong dev, ubyte fnc) 
    {
        import std.bitmanip : write;
        assert(dev <= 255, "device number can't be more 255");
        buffer[].write(cast(ubyte)dev, 0);
        buffer[].write(fnc, 1);
        return buffer[0..2];
    }

    int peekDF(const(void)[] vbuf, ref ulong dev, ref ubyte fnc)
    {
        import std.bitmanip : peek;
        auto buf = cast(const(ubyte)[])vbuf;
        if (buf.length >= 1) dev = buf.peek!ubyte(0);
        else return 2;
        if (buf.length >= 2) fnc = buf.peek!ubyte(1);
        else return 1;
        return 0;
    }

    const(void)[] pack(const(void)[] data)
    {
        final switch (data.length) foreach (T; Types)
            case T.sizeof: return typedPack((cast(T[])data)[0]);
    }

    const(void)[] unpack(const(void)[] data)
    {
        final switch (data.length) foreach (T; Types)
            case T.sizeof: return typedUnpack!T(data);
    }
}

version(unittest)
{
    void[] tb(T)(T value) { return cast(void[])[value]; }
    T bt(T)(const(void)[] data) { return (cast(T[])data)[0]; }
}

unittest
{
    auto bsp = new BasicSpecRules;
    assert(cast(ubyte[])bsp.packT(cast(ubyte)(0xAB)) == [0xAB]);
    assert(cast(ubyte[])bsp.packT(cast(ushort)(0xA1B2)) == [0xA1, 0xB2]);
    assert(cast(ubyte[])bsp.packT(cast(int)(0xA1B2C3D4)) ==
            [0xC3, 0xD4, 0xA1, 0xB2]);
    assert(cast(ubyte[])bsp.pack(tb(0xA1B2C3D4E5F6A7B8)) ==
            [0xA7, 0xB8, 0xE5, 0xF6, 0xC3, 0xD4, 0xA1, 0xB2]);

    assert(bt!ulong(bsp.unpack(cast(ubyte[])[0xA7,0xB8,0xE5,0xF6,0xC3,0xD4,0xA1,0xB2])) ==
            0xA1B2C3D4E5F6A7B8);

    import std.random;
    void test(T)()
    {
        auto val = cast(T)uniform(0, T.max);
        assert(bsp.unpackT!T(bsp.packT(val)) == val);
    }
    foreach (ubyte i; 0 .. 256)
        assert(bsp.unpackT!ubyte(bsp.packT(i)) == i);

    foreach (i; 0 .. 10_000) test!ushort;
    foreach (i; 0 .. 10_000) test!uint;
    foreach (i; 0 .. 10_000) test!ulong;
}