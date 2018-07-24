///
module modbus.backend.tcp;

import std.bitmanip;

import modbus.backend.base;

///
class TCP : BaseBackend
{
protected:
    // transaction id size + protocol id size + packet length size
    enum packetServiceData = ushort.sizeof * 3;
    enum packetLengthOffset = ushort.sizeof * 2;
public:
    ///
    this(SpecRules s=null)
    { super(s, packetServiceData, packetServiceData); }

protected override:
    void startMessage(void[] buf, ref size_t idx, ulong dev, ubyte fnc, ulong stamp)
    {
        const ushort zero;
        // transaction id
        append(buf, idx, cast(ushort)stamp);
        // protocol id
        append(buf, idx, zero);
        // packet length (change in finalizeMessage)
        append(buf, idx, zero);
        appendDF(buf, idx, dev, fnc);
    }

    void finalizeMessage(void[] buf, ref size_t idx)
    {
        auto dsize = cast(ushort)(idx - packetServiceData);
        size_t plo = packetLengthOffset;
        append(buf, plo, dsize);
    }

    bool check(const(void)[] data)
    {
        enum plo = packetLengthOffset;
        auto lenbytes = cast(ubyte[2])data[plo..plo+ushort.sizeof];
        auto len = bigEndianToNative!ushort(lenbytes);
        return len == (data.length - packetServiceData);
    }

    ulong getStamp(const(void)[] data)
    { return bigEndianToNative!ushort((cast(ubyte[2])data[0..2])); }

    size_t endDataSplit() @property { return 0; }
}

unittest
{
    import std.array : appender;
    void[100] data = void;
    auto tcp = new TCP();
    int xx = 123;
    auto res = cast(ubyte[])tcp.buildMessage(data, 1, 2, 0, xx);
    assert (res == [0,0, 0,0, 0,6, 1, 2, 0,123,0,0]);
    assert (tcp.check(res));
}