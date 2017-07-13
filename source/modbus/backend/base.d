///
module modbus.backend.base;

version (modbus_verbose)
    public import std.experimental.logger;

import modbus.protocol;
public import modbus.exception;
public import modbus.backend.connection;
public import modbus.backend.specrules;

/++ Basic functionality of Modbus.Backend

    Params:
    BUFFER_SIZE = static size of message buffer
 +/
class BaseBackend(size_t BUFFER_SIZE) : Modbus.Backend
{
protected:
    enum functionTypeSize = 1;
    Connection conn;
    SpecRules sr;

    ubyte[BUFFER_SIZE] buffer;
    size_t idx;
    immutable size_t minimumMsgLength;
    immutable size_t devOffset;
    immutable size_t serviceData;

public:

    /++
        Params:
            c = connection
            s = rules for pack N-byte data to sending package
            serviceData = size of CRC for RTU, protocol id for TCP etc
            deviceOffset = offset of device number (address) in message
     +/
    this(Connection c, SpecRules s, size_t serviceData, size_t deviceOffset)
    {
        if (c is null)
            throw modbusException("connection is null");
        conn = c;
        sr = s !is null ? s : new BasicSpecRules;
        this.serviceData = serviceData;
        devOffset = deviceOffset;

        minimumMsgLength = serviceData + sr.deviceTypeSize + functionTypeSize;
    }

    protected void preStart() { idx = 0; }
    protected void preRead() { idx = 0; }

    ///
    abstract void startAlgo(ulong dev, ubyte func);
    ///
    abstract Response readAlgo(size_t expectedBytes);

    override
    {
        abstract void send();

        ///
        void start(ulong dev, ubyte func)
        {
            preStart();
            startAlgo(dev, func);
        }

        ///
        Response read(size_t expectedBytes)
        {
            preRead();
            return readAlgo(expectedBytes);
        }

        void append(byte v) { append(sr.pack(v)); }
        void append(short v) { append(sr.pack(v)); }
        void append(int v) { append(sr.pack(v)); }
        void append(long v) { append(sr.pack(v)); };
        void append(float v) { append(sr.pack(v)); };
        void append(double v) { append(sr.pack(v)); };

        void append(const(void)[] v)
        {
            scope (failure) idx = 0;
            auto inc = v.length;
            if (idx + inc + serviceData >= buffer.length)
                throw modbusException("many args");
            buffer[idx..idx+inc] = cast(ubyte[])v;
            idx += inc;
            version (modbus_verbose)
                .trace("append msg buffer data: ", buffer[0..idx]);
        }

        const(void)[] tempBuffer() const @property { return buffer[0..idx]; }
    }

protected:

    void appendDF(ulong dev, ubyte fnc) { append(sr.packDF(dev, fnc)); }

    Response baseRead(size_t expectedBytes, bool allocateOnlyExpected=false)
    {
        expectedBytes += minimumMsgLength;
        version (modbus_verbose) .tracef("start read %d bytes", expectedBytes);

        auto buf = buffer[];
        if (allocateOnlyExpected) buf = buf[0..expectedBytes];
        auto tmp = cast(ubyte[])conn.read(buf);
        idx = tmp.length;
        version (modbus_verbose) .trace(" readed bytes: ", tmp);

        if (tmp.length < devOffset+sr.deviceTypeSize+functionTypeSize)
            throw readDataLengthException(0, 0, expectedBytes, tmp.length);

        Response res;
        sr.peekDF(tmp[devOffset..$], res.dev, res.fnc);
        res.data = tmp;

        if (tmp.length < minimumMsgLength+1)
            throw readDataLengthException(res.dev, res.fnc, expectedBytes, tmp.length);

        if (res.data.length > expectedBytes)
        {
            version (modbus_verbose)
                .warningf("receive more bytes what expected (%d): %(0x%02x %)",
                            expectedBytes, tmp[expectedBytes..$]);

            res.data = res.data[0..expectedBytes];
        }

        return res;
    }
}