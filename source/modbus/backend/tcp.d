///
module modbus.backend.tcp;

import modbus.backend.base;

///
class TCP : BaseBackend!260
{
protected:
    // transaction id size + protocol id size + packet length size
    enum packedServiceData = 2 + 2 + 2;
public:
    ///
    this(Connection c) { super(c, packedServiceData, 6); }

override:

    ///
    void start(ubyte dev, ubyte func)
    {
        // transaction id
        this.write(ushort(0));
        // protocol id
        this.write(ushort(0));
        // packet length (change in send)
        this.write(ushort(0));
        this.write(dev);
        this.write(func);
    }

    ///
    void send()
    {
        import std.bitmanip : nativeToBigEndian;
        scope (exit) idx = 0;
        auto dsize = cast(ushort)(idx - packedServiceData);
        buffer[4..6] = nativeToBigEndian(dsize);
        conn.write(buffer[0..idx]);

        debug (modbus_verbose)
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

        res.data = tmp[devOffset+2..$];

        return res;
    }
}