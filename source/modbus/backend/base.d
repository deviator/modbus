///
module modbus.backend.base;

version (modbusverbose)
    public import std.experimental.logger;

import modbus.protocol;
public import modbus.exception;
public import modbus.backend.connection;

/++ Basic functionality of Modbus.Backend

    Params:
    BUFFER_SIZE - static size of message buffer
 +/
class BaseBackend(size_t BUFFER_SIZE) : Modbus.Backend
{
protected:
    Connection conn;
    ubyte[BUFFER_SIZE] buffer;
    size_t idx;
    immutable size_t minimumMsgLength;
    immutable size_t devOffset;
    immutable size_t funcOffset;
    immutable size_t serviceData;

public:

    /++
        Params:
        c - connection
        serviceData - CRC for RTU, protocol id for TCP etc
        deviceOffset - offset of device number in message
        functionOffset - offset of function number in message
     +/
    this(Connection c, size_t serviceData, size_t deviceOffset, ptrdiff_t functionOffset=-1)
    {
        if (c is null) throw modbusException("connection is null");
        conn = c;
        this.serviceData = serviceData;
        devOffset = deviceOffset;
        funcOffset = functionOffset != -1 ? functionOffset : deviceOffset + 1;
        minimumMsgLength = serviceData + 2; // dev and func
    }

    abstract override
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
            scope (failure) idx = 0;
            auto inc = v.length;
            if (idx + inc + serviceData >= buffer.length)
                throw modbusException("many args");
            buffer[idx..idx+inc] = cast(ubyte[])v;
            idx += inc;
            version (modbusverbose)
                .trace("append msg buffer data: ", buffer[0..idx]);
        }

        bool messageComplite() const @property { return idx == 0; }
        const(void)[] tempBuffer() const @property { return buffer[0..idx]; }
    }

protected:

    void write(T)(T v)
    {
        static import std.bitmanip;
        alias bwrite = std.bitmanip.write;
        scope (failure) idx = 0;
        if (idx + T.sizeof + serviceData >= buffer.length)
            throw modbusException("many args");
        bwrite(buffer[], v, &idx);
        version (modbusverbose)
            .trace("append msg buffer data: ", buffer[0..idx]);
    }

    Response baseRead(size_t expectedBytes, bool allocateOnlyExpected=false)
    {
        expectedBytes += minimumMsgLength;

        auto buf = buffer[];
        if (allocateOnlyExpected) buf = buf[0..expectedBytes];
        auto tmp = cast(ubyte[])conn.read(buf);

        version (modbusverbose)
            .trace(" read bytes: ", tmp);

        Response res;
        res.dev = tmp.length < devOffset+1 ? 0 : tmp[devOffset];
        res.fnc = tmp.length < funcOffset+1 ? 0 : tmp[funcOffset];
        res.data = tmp;

        if (tmp.length < minimumMsgLength+1)
            throw readDataLengthException(res.dev, res.fnc, expectedBytes, tmp.length);

        if (res.data.length > expectedBytes)
        {
            version (modbusverbose)
                .warningf("receive more bytes what expected (%d): %(0x%02x %)",
                            expectedBytes, tmp[expectedBytes..$]);

            res.data = res.data[0..expectedBytes];
        }

        return res;
    }
}