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
}

///
class BasicSpecRules : SpecRules
{
    protected ubyte[16] buffer;

    private const(void)[] tpack(T)(T v) @nogc
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
        import std.meta : AliasSeq;
        union cst(T)
        {
            T v;
            void[T.sizeof] data;
            this (const(void)[] buf) { data[] = buf[]; }
        }
        final switch (data.length)
            foreach (T; AliasSeq!(byte,short,int,long))
                case T.sizeof: return tpack(cst!T(data).v);
    }
}

version(unittest)
    void[] tb(T)(T value) { return cast(void[])[value]; }

unittest
{
    auto bsp = new BasicSpecRules;
    assert(cast(ubyte[])bsp.pack(tb(cast(ubyte)(0xAB))) == [0xAB]);
    assert(cast(ubyte[])bsp.pack(tb(cast(ushort)(0xA1B2))) == [0xA1, 0xB2]);
    assert(cast(ubyte[])bsp.pack(tb(cast(int)(0xA1B2C3D4))) ==
            [0xC3, 0xD4, 0xA1, 0xB2]);
    assert(cast(ubyte[])bsp.pack(tb(0xA1B2C3D4E5F6A7B8)) ==
            [0xA7, 0xB8, 0xE5, 0xF6, 0xC3, 0xD4, 0xA1, 0xB2]);
}