///
module modbus.backend.specrules;

version (modbus_verbose)
    import std.experimental.logger;

///
interface SpecRules
{
pure:
    ///
    @property size_t deviceTypeSize();

    ///
    const(void)[] packDF(ulong dev, ubyte fnc);
    ///
    void peekDF(const(void)[] buf, ref ulong dev, ref ubyte fnc);

    ///
    const(void)[] pack(byte);
    ///
    const(void)[] pack(short);
    ///
    const(void)[] pack(int);
    ///
    const(void)[] pack(long);
    ///
    const(void)[] pack(float);
    ///
    const(void)[] pack(double);
}

///
class BasicSpecRules : SpecRules
{
protected:
    ubyte[16] buffer;

public:

pure:

    override
    {
        @property size_t deviceTypeSize() { return 1; }

        const(void)[] packDF(ulong dev, ubyte fnc) 
        {
            import std.bitmanip : write;
            assert(dev <= 255, "device number can't be more 255");
            buffer[].write(cast(ubyte)dev, 0);
            buffer[].write(fnc, 1);
            return buffer[0..2];
        }

        void peekDF(const(void)[] vbuf, ref ulong dev, ref ubyte fnc)
        {
            import std.bitmanip : peek;
            auto buf = cast(const(ubyte)[])vbuf;
            if (buf.length >= 1) dev = buf.peek!ubyte(0);
            else version (modbus_verbose) debug
                .error("short readed message: can't read device number");
            if (buf.length >= 2) fnc = buf.peek!ubyte(1);
            else version (modbus_verbose) debug
                .error("short readed message: can't read function number");
        }

        const(void)[] pack(byte v) { return tpack(v); }
        const(void)[] pack(short v) { return tpack(v); }
        const(void)[] pack(int v) { return tpack(v); }
        const(void)[] pack(long v) { return tpack(v); }
        const(void)[] pack(float v) { return tpack(v); }
        const(void)[] pack(double v) { return tpack(v); }
    }

private:

    const(void)[] tpack(T)(T v)
    {
        import std.bitmanip : write;

        static if (T.sizeof <= ushort.sizeof)
            buffer[].write(v, 0);
        else
        {
            size_t i;
            foreach (part; cast(ushort[])(cast(void[])[v]))
                buffer[].write(part, &i);
        }

        return buffer[0..T.sizeof];
    }
}

unittest
{
    auto bsp = new BasicSpecRules;
    assert(cast(ubyte[])bsp.pack(cast(ubyte)(0xAB)) == [0xAB]);
    assert(cast(ubyte[])bsp.pack(cast(ushort)(0xA1B2)) == [0xA1, 0xB2]);
    assert(cast(ubyte[])bsp.pack(cast(int)(0xA1B2C3D4)) ==
            [0xC3, 0xD4, 0xA1, 0xB2]);
    assert(cast(ubyte[])bsp.pack(0xA1B2C3D4E5F6A7B8) ==
            [0xA7, 0xB8, 0xE5, 0xF6, 0xC3, 0xD4, 0xA1, 0xB2]);
}

///
class PilotBMSSpecRules : BasicSpecRules
{
public pure override:
    @property size_t deviceTypeSize() { return 4; }

    const(void)[] packDF(ulong dev, ubyte fnc) 
    {
        import std.bitmanip : write;
        size_t idx = 0;
        buffer[].write(cast(ushort)(dev), &idx);
        buffer[].write(cast(ushort)(dev>>16), &idx);
        buffer[].write(fnc, &idx);
        return buffer[0..idx];
    }

    void peekDF(const(void)[] vbuf, ref ulong dev, ref ubyte fnc)
    {
        import std.bitmanip : peek;
        size_t idx = 0;
        auto buf = cast(const(ubyte)[])vbuf;
        if (buf.length >= 4)
        {
            const a = buf.peek!ushort(&idx);
            const b = buf.peek!ushort(&idx);
            dev = (b << 16) | a;
        }
        else version (modbus_verbose) debug
            .error("short readed message: can't read device number");
        if (buf.length >= idx) fnc = buf.peek!ubyte(idx);
        else version (modbus_verbose) debug
            .error("short readed message: can't read function number");
    }
}