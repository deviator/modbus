module modbus.backend.base;

public import std.experimental.logger;
public import std.exception : enforce;

import modbus.protocol;
public import modbus.exception;
public import modbus.backend.connection;

version (unittest) static this() { sharedLog = new NullLogger; }

class BaseBackend(size_t BUFFER_SIZE) : Modbus.Backend
{
protected:
    Connection c;
    ubyte[BUFFER_SIZE] buffer;
    size_t idx;
    immutable(size_t) minimumMsgLength;
    immutable(size_t) devOffset;

public:
    this(Connection c, size_t minMsgLen, size_t deviceOffset)
    {
        this.c = enforce(c, new ModbusException("connection is null"));
        minimumMsgLength = minMsgLen;
        devOffset = deviceOffset;
    }

    abstract
    {
        void start(ubyte dev, ubyte func);
        void send();
        Response read(size_t expectedBytes);
    }

    override
    {
        void append(byte v) { this.write(v); }
        void append(ubyte v) { this.write(v); }
        void append(short v) { this.write(v); }
        void append(ushort v) { this.write(v); }
        void append(int v) { this.write(v); }
        void append(uint v) { this.write(v); };
        void append(long v) { this.write(v); };
        void append(ulong v) { this.write(v); };
        void append(float v) { this.write(v); };
        void append(double v) { this.write(v); };

        void append(const(void)[] v)
        {
            auto inc = v.length;
            //                 CRC
            enforce(inc + idx + 2 < buffer.length,
                new ModbusException("many args"));
            buffer[idx..idx+inc] = cast(ubyte[])v;
            idx += inc;
        };

        bool messageComplite() const @property { return idx == 0; }
        const(void)[] tempBuffer() const @property { return buffer[0..idx]; }
    }

protected:

    void write(T)(T v)
    {
        import std.bitmanip : write;
        scope (failure) idx = 0;
        //                      CRC
        enforce(T.sizeof + idx + 2 < buffer.length,
                new ModbusException("many args"));
        buffer[].write(v, &idx);
    }

    Response baseRead(size_t expectedBytes)
    {
        expectedBytes += minimumMsgLength;

        auto tmp = cast(ubyte[])c.read(buffer[]);
        .trace(" read bytes: ", tmp);

        Response res;
        res.dev = tmp.length < devOffset+1 ? 0 : tmp[devOffset+0];
        res.fnc = tmp.length < devOffset+2 ? 0 : tmp[devOffset+1];
        res.data = tmp;

        enforce(tmp.length >= minimumMsgLength+1,
            new ReadDataLengthException(res.dev, res.fnc, expectedBytes, tmp.length));

        if (res.data.length > expectedBytes)
        {
            .warningf("receive more bytes what expected (%d): %(0x%02x %)",
                        expectedBytes, tmp[expectedBytes..$]);

            res.data = res.data[0..expectedBytes];
        }

        return res;
    }
}