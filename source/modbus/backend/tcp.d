///
module modbus.backend.tcp;

import modbus.backend.base;

///
class TCP : BaseBackend!260
{
    ///
    this(Connection c)
    {
        super(c,
        2 + // transaction id
        2 + // protocol id
        2 + // packet length
        1 + // dev
        1,  // fnc
        6   // device number offset
        );
    }

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
        scope (exit) idx = 0;
        // 6 is transport id and protocol id and pack length sizes
        auto dsize = cast(ushort)(idx - 6);

        import std.bitmanip : nativeToBigEndian;
        buffer[4..6] = nativeToBigEndian(dsize);
        c.write(buffer[0..idx]);
        .trace("write bytes: ", buffer[0..idx]);
    }

    ///
    Response read(size_t expectedBytes)
    {
        auto res = baseRead(expectedBytes, true);
        auto tmp = cast(ubyte[])res.data;

        import std.bitmanip : bigEndianToNative;
        auto plen = bigEndianToNative!ushort(cast(ubyte[2])tmp[4..6]);

        //                       ids and pack len
        enforce(tmp.length == plen+6,
            new ReadDataLengthException(res.dev, res.fnc, plen+6, tmp.length));

        res.data = tmp[devOffset+2..$];

        return res;
    }
}
