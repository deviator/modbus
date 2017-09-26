///
module modbus.backend.base;

version (modbus_verbose)
    public import std.experimental.logger;

import std.traits;

import modbus.types;
public import modbus.exception;
public import modbus.connection;
public import modbus.backend.specrules;

/// Message builder and parser
interface Backend
{
    /++ work on preallocated buffer
        Returns:
            slice of preallocated buffer
     +/
    final void[] buildMessage(Args...)(void[] buffer, ulong dev, ubyte fnc, Args args)
    {
        size_t idx = 0;
        startMessage(buffer, idx, dev, fnc);
        void _append(T)(T val)
        {
            static if (isArray!T)
            {
                import std.range : ElementType;
                static if (is(Unqual!(ElementType!T) == void))
                    appendBytes(buffer, idx, val);
                else foreach (e; val) _append(e);
            }
            else
            {
                static if (is(T == struct))
                    foreach (v; val.tupleof) _append(v);
                else static if (isNumeric!T) append(buffer, idx, val);
                else static assert(0, "unsupported type " ~ T.stringof);
            }
        }
        foreach (arg; args) _append(arg);
        completeMessage(buffer, idx);
        return buffer[0..idx];
    }

    ///
    enum ParseResult
    {
        success, ///
        errorMsg, /// error message (fnc >= 0x80)
        uncomplete, ///
        checkFail /// for RTU check CRC fail
    }

    /++ Read data to temp message buffer
        Params:
        data = parsing data buffer, CRC and etc
        result = reference to result message
        +/
    ParseResult parseMessage(const(void)[] data, ref Message result);

    size_t minMsgLength() @property;
    size_t notMessageDataLength() @property;

protected:

    /// start building message
    void startMessage(void[] buf, ref size_t idx, ulong dev, ubyte func);

    /// append data to message buffer
    final void append(T)(void[] buf, ref size_t idx, T val)
        if (isNumeric!T && !is(T == real))
    {
        union cst { T value; void[T.sizeof] data; }
        appendBytes(buf, idx, pack(cst(val).data[]));
    }
    /// ditto
    void appendBytes(void[] buf, ref size_t idx, const(void)[]);
    /// finalize message
    void completeMessage(void[] buf, ref size_t idx);

    /// pack data to need layout for sending
    const(void)[] pack(const(void)[]);
}

/++ Basic functionality of Backend
 +/
abstract class BaseBackend : Backend
{
protected:
    enum functionTypeSize = 1;
    SpecRules sr;

    immutable size_t _minMsgLength;
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
    this(SpecRules s, size_t serviceData, size_t deviceOffset)
    {
        this.sr = s !is null ? s : new BasicSpecRules;
        this.serviceData = serviceData;
        this.devOffset = deviceOffset;
        _minMsgLength = serviceData + sr.deviceTypeSize + functionTypeSize + ubyte.sizeof;
    }

    override
    {
        ParseResult parseMessage(const(void)[] data, ref Message msg)
        {
            if (data.length < startDataSplit+1+endDataSplit)
                return ParseResult.uncomplete;
            if (auto err = sr.peekDF(data[devOffset..$], msg.dev, msg.fnc))
                return ParseResult.uncomplete;
            auto ret = ParseResult.success;
            if (msg.fnc >= 0x80)
            {
                data = data[0..startDataSplit+1+endDataSplit];
                ret = ParseResult.errorMsg;
            }
            msg.data = data[startDataSplit..$-endDataSplit];
            if (!check(data)) return ParseResult.checkFail;
            return ret;
        }

        size_t minMsgLength() @property { return _minMsgLength; }
        size_t notMessageDataLength() @property
        { return serviceData + sr.deviceTypeSize + functionTypeSize; }
    }

protected:

    override
    {
        void appendBytes(void[] buf, ref size_t idx, const(void)[] v)
        {
            auto inc = v.length;
            if (idx + inc + serviceData >= buf.length)
                throw modbusException("many args");
            buf[idx..idx+inc] = v[];
            idx += inc;
            version (modbus_verbose)
                .trace("append msg buffer data: ", buf[0..idx]);
        }

        const(void)[] pack(const(void)[] data) { return sr.pack(data); }
    }

    abstract
    {
        void startMessage(void[] buf, ref size_t idx, ulong dev, ubyte func);
        void completeMessage(void[] buf, ref size_t idx);

        bool check(const(void)[] data);
        size_t endDataSplit() @property;
    }

    size_t startDataSplit() @property
    { return devOffset + sr.deviceTypeSize + functionTypeSize; }

    void appendDF(void[] buf, ref size_t idx, ulong dev, ubyte fnc)
    { appendBytes(buf, idx, sr.packDF(dev, fnc)); }
}