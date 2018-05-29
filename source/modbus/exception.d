///
module modbus.exception;

import std.string : format;
import std.datetime : Duration;

import modbus.types;

public import serialport.exception;

///
class ModbusException : Exception
{ private this() @safe pure nothrow @nogc { super(""); } }

///
class ModbusIOException : ModbusException
{
    ///
    ulong dev;
    ///
    ubyte fnc;

    private this() @safe pure nothrow @nogc { super(); }
}

///
class ModbusDevException : ModbusIOException
{
    ///
    private ubyte[260] writeBuffer;
    ///
    private size_t writeLength;
    ///
    private ubyte[260] readBuffer;
    ///
    private size_t readLength;

    private this() @safe pure nothrow @nogc { super(); }

    @property
    {
        void writed(const(void)[] b)
        {
            auto ln = b.length;
            writeBuffer[0..ln] = cast(ubyte[])(b[0..ln]);
            writeLength = ln;
        }

        const(void)[] writed() const
        { return writeBuffer[0..writeLength]; }

        void readed(const(void)[] b)
        {
            auto ln = b.length;
            readBuffer[0..ln] = cast(ubyte[])(b[0..ln]);
            readLength = ln;
        }

        const(void)[] readed() const
        { return readBuffer[0..readLength]; }
    }
}

///
class CheckFailException : ModbusDevException
{ private this() @safe pure nothrow @nogc { super(); } }

///
class FunctionErrorException : ModbusDevException
{
    ///
    FunctionErrorCode code;

    private this() @safe pure nothrow @nogc { super(); }
}

/// use this exception for throwing errors in modbus slave
class SlaveFuncProcessException : ModbusIOException
{
    ///
    FunctionErrorCode code;

    private this() @safe pure nothrow @nogc { super(); }
}

///
class ReadDataLengthException : ModbusDevException
{
    ///
    size_t expected, responseLength;

    private this() @safe pure nothrow @nogc { super(); }
}

private E setFields(E: ModbusException)(E e, string msg, string file,
                                            size_t line)
{
    e.msg = msg;
    e.file = file;
    e.line = line;
    return e;
}

private string extraFields(E, string[] fields)()
{
    static if (fields.length == 0) return "";
    else
    {
        string ret;

        static foreach (field; fields)
        {{
            mixin(`alias ft = typeof(E.init.%s);`.format(field));
            ret ~= `%s %s, `.format(ft.stringof, field);
        }}

        return ret;
    }
}

unittest
{
    static assert(extraFields!(ModbusIOException, ["dev", "fnc"]) ==
                    "ulong dev, ubyte fnc, ");
}

private string extraFieldsSet(string name, string[] fields)
{
    if (fields.length == 0) return "";

    string ret;

    foreach (field; fields)
        ret ~= "%1$s.%2$s = %2$s;\n".format(name, field);

    return ret;
}

import std.format;

enum preallocated;

private mixin template throwExcMix(E, string[] fields=[])
    if (is(E: ModbusException))
{
    enum name = E.stringof;
    mixin(`
    @preallocated
    private %1$s %2$s%1$s;
    void throw%1$s(%3$s string msg="", string file=__FILE__,
                        size_t line=__LINE__) @nogc
    {
        auto e = %2$s%1$s.setFields(msg, file, line);
        %4$s
        throw e;
    }
    `.format(name, "prealloc", extraFields!(E,fields),
                extraFieldsSet("e", fields))
    );
}

mixin throwExcMix!ModbusException;
mixin throwExcMix!(ModbusIOException, ["dev", "fnc"]);
mixin throwExcMix!(ModbusDevException, ["dev", "fnc"]);
mixin throwExcMix!(CheckFailException, ["dev", "fnc"]);
mixin throwExcMix!(FunctionErrorException, ["dev", "fnc", "code"]);
mixin throwExcMix!(SlaveFuncProcessException, ["dev", "fnc", "code"]);
mixin throwExcMix!(ReadDataLengthException, ["dev", "fnc", "expected",
                                                "responseLength"]);

static this()
{
    import std.traits : getSymbolsByUDA;
    static foreach (sym; getSymbolsByUDA!(mixin(__MODULE__), preallocated))
        sym = new typeof(sym);
}