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
    /++ Full build message for sending

        work on preallocated buffer

        Params:
            buf = preallocated buffer
            dev = modbus device number
            fnc = function number
            args = message data

        Returns:
            slice of preallocated buffer with message
     +/
    void[] buildMessage(Args...)(void[] buf, ulong dev, ubyte fnc, Args args)
    {
        size_t idx;
        startMessage(buf, idx, dev, fnc);
        recursiveAppend(buf, idx, args);
        finalizeMessage(buf, idx);
        return buf[0..idx];
    }

    ///
    void recursiveAppend(Args...)(void[] buf, ref size_t idx, Args args)
        if (Args.length >= 1)
    {
        static if (Args.length == 1)
        {
            auto val = args[0];
            static if (isArray!T)
            {
                import std.range : ElementType;
                static if (is(Unqual!(ElementType!T) == void))
                    appendBytes(buf, idx, val);
                else foreach (e; val) recursiveAppend(buf, idx, e);
            }
            else
            {
                static if (is(T == struct))
                    foreach (v; val.tupleof) recursiveAppend(buf, idx, v);
                else static if (isNumeric!T) append(buf, idx, val);
                else static assert(0, "unsupported type " ~ T.stringof);
            }
        }
        else static foreach (arg; args) recursiveAppend(buf, idx, arg);
    }

    ///
    enum ParseResult
    {
        success, ///
        incomplete, ///
        checkFails ///
    }

    /++ Read data to temp message buffer
        Params:
            data = parsing data buffer, CRC and etc
            result = reference to result message
        +/
    ParseResult parseMessage(const(void)[] data, ref Message result);

    ///
    size_t aduLength(size_t dataBytes=0);

    const(void)[] packT(T)(T value) { return sr.packT(value); }
    T unpackT(T)(const(void)[] data) { return sr.unpackT!T(data); }
    T unpackTT(T)(T value) { return sr.unpackT!T(cast(void[])[value]); }

protected:

    SpecRules sr() @property;

    /// start building message
    void startMessage(void[] buf, ref size_t idx, ulong dev, ubyte fnc);

    /// append data to message buffer
    void append(T)(void[] buf, ref size_t idx, T val)
        if (isNumeric!T && !is(T == real))
    {
        union cst { T value; void[T.sizeof] data; }
        appendBytes(buf, idx, sr.pack(cst(val).data[]));
    }
    /// ditto
    void appendBytes(void[] buf, ref size_t idx, const(void)[]);
    ///
    void finalizeMessage(void[] buf, ref size_t idx);
}

/++ Basic functionality of Backend
 +/
abstract class BaseBackend : Backend
{
protected:
    enum functionTypeSize = 1;
    SpecRules specRules;

    immutable size_t devOffset;
    immutable size_t serviceData;

    override SpecRules sr() @property { return specRules; }

public:

    /++
        Params:
            s = rules for pack N-byte data to sending package
            serviceData = size of CRC for RTU, protocol id for TCP etc
            deviceOffset = offset of device number (address) in message
     +/
    this(SpecRules s, size_t serviceData, size_t deviceOffset)
    {
        import std.exception : enforce;
        this.specRules = s !is null ? s : new BasicSpecRules;
        this.serviceData = serviceData;
        this.devOffset = deviceOffset;
    }

    override
    {
        ParseResult parseMessage(const(void)[] data, ref Message msg)
        {
            if (data.length < aduLength)
                return ParseResult.incomplete;
            if (auto err = sr.unpackDF(data[devOffset..$], msg.dev, msg.fnc))
                return ParseResult.incomplete;
            if (!check(data)) return ParseResult.checkFails;

            msg.data = data[startDataSplit..$-endDataSplit];
            return ParseResult.success;
        }

        size_t aduLength(size_t dataBytes=0)
        {
            return serviceData +
                   sr.deviceTypeSize +
                   functionTypeSize +
                   dataBytes; 
        }
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
    }

    abstract
    {
        void startMessage(void[] buf, ref size_t idx, ulong dev, ubyte func);
        void finalizeMessage(void[] buf, ref size_t idx);

        bool check(const(void)[] data);
        size_t endDataSplit() @property;
    }

    size_t startDataSplit() @property
    { return devOffset + sr.deviceTypeSize + functionTypeSize; }

    void appendDF(void[] buf, ref size_t idx, ulong dev, ubyte fnc)
    { appendBytes(buf, idx, sr.packDF(dev, fnc)); }
}