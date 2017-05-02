///
module modbus.backend.tcp;

import modbus.backend.base;

///
class TCP : BaseBackend!260
{
protected:
    // transaction id size + protocol id size + packet length size
    enum packedServiceData = ushort.sizeof * 3;
    enum packedLengthOffset = ushort.sizeof * 2;
public:
    ///
    this(Connection c, SpecRules s=null)
    { super(c, s, packedServiceData, packedServiceData); }

override:

    ///
    void start(ulong dev, ubyte func)
    {
        // transaction id
        append(ushort(0));
        // protocol id
        append(ushort(0));
        // packet length (change in send)
        append(ushort(0));
        appendDF(dev, func);
    }

    ///
    void send()
    {
        import std.bitmanip : nativeToBigEndian;
        scope (exit) idx = 0;
        auto dsize = cast(ushort)(idx - packedServiceData);
        enum plo = packedLengthOffset;
        buffer[plo..plo+ushort.sizeof] = nativeToBigEndian(dsize);
        conn.write(buffer[0..idx]);

        version (modbus_verbose)
            .trace("write bytes: ", buffer[0..idx]);
    }

    ///
    Response read(size_t expectedBytes)
    {
        import std.bitmanip : bigEndianToNative;

        auto res = baseRead(expectedBytes, true);
        auto tmp = cast(ubyte[])res.data;

        auto plen = bigEndianToNative!ushort(cast(ubyte[2])tmp[4..6]);

        if (tmp.length != plen+packedServiceData)
            throw readDataLengthException(res.dev, res.fnc,
                            plen+packedServiceData, tmp.length);

        res.data = tmp[devOffset+sr.deviceTypeSize+functionTypeSize..$];

        return res;
    }
}