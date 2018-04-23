///
module modbus.exception;

import std.string : format;
import std.datetime : Duration;

enum MINIMUM_MODBUS_MSG_LENGTH = 5;

///
class ModbusException : Exception
{
    ///
    this(string msg, string file=__FILE__, size_t line=__LINE__)
        @nogc @safe pure nothrow
    { super(msg, file, line); }
}

///
class ModbusIOException : ModbusException
{
    ///
    ulong dev;
    ///
    ubyte fnc;

    this(string msg, ulong dev, ubyte fnc,
            string file=__FILE__, size_t line=__LINE__)
        @nogc @safe pure nothrow
    {
        super(msg, file, line);
        this.dev = dev;
        this.fnc = fnc;
    }
}

///
class ModbusTimeoutException : ModbusIOException
{
    ///
    Duration dur;
    ///
    this(string msg, ulong dev, ubyte fnc, Duration dur,
            string file=__FILE__, size_t line=__LINE__)
        @nogc @safe pure nothrow
    {
        super(msg, dev, fnc, file, line);
        this.dur = dur;
    }
}

///
class ModbusDevException : ModbusIOException
{
    ///
    private ubyte[256] writeBuffer;
    ///
    private size_t writeLength;
    ///
    private ubyte[256] readBuffer;
    ///
    private size_t readLength;

    ///
    this(ulong dev, ubyte fnc, string msg,
         string file=__FILE__, size_t line=__LINE__)
    { super(msg, dev, fnc, file, line); }

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
{
    ///
    this(ulong dev, ubyte fnc,
         string file=__FILE__, size_t line=__LINE__)
    {
        super(dev, fnc, format("dev %d fnc %d(0x%x) recive msg CRC check fails",
                    dev, fnc, fnc), file, line);
    }
}

///
class FunctionErrorException : ModbusDevException
{
    ///
    ubyte res;
    ///
    FunctionErrorCode code;

    ///
    this(ulong dev, ubyte fnc, ubyte res, ubyte code,
         string file=__FILE__, size_t line=__LINE__)
    {
        this.res = res;
        this.code = cast(FunctionErrorCode)code;

        super(dev, fnc, format("dev %d fnc %d(0x%x) recive fnc %d(0x%x) with "~
                                "exception code %s (%d)", dev, fnc, fnc, res, res,
                                cast(FunctionErrorCode)code, code), file, line);
    }
}

/// use this exception for throwing errors in modbus slave
class SlaveFuncProcessException : ModbusIOException
{
    ///
    FunctionErrorCode code;

    ///
    this(ulong dev, ubyte fnc, FunctionErrorCode c)
    {
        code = c;
        super("error while process message", dev, fnc);
    }
}

///
class ReadDataLengthException : ModbusDevException
{
    size_t expected, responseLength;
    ///
    this(ulong dev, ubyte fnc, size_t exp, size_t res,
         string file=__FILE__, size_t line=__LINE__)
    {
        expected = exp;
        responseLength = res;
        super(dev, fnc, format("dev %d fnc to %d(0x%x) recieves wrong"~
                    " count of bytes (%d != expected %d or more what %d)",
                    dev, fnc, fnc, res, exp, MINIMUM_MODBUS_MSG_LENGTH), file, line);
    }
}

///
enum FunctionErrorCode : ubyte
{
    ILLEGAL_FUNCTION     = 1, /// 1
    ILLEGAL_DATA_ADDRESS = 2, /// 2
    ILLEGAL_DATA_VALUE   = 3, /// 3
    SLAVE_DEVICE_FAILURE = 4, /// 4
    ACKNOWLEDGE          = 5, /// 5
    SLAVE_DEVICE_BUSY    = 6, /// 6
    MEMORY_PARITY_ERROR  = 8, /// 8
    GATEWAY_PATH_UNAVAILABLE = 0xA, /// 0xA
    GATEWAY_TARGET_DEVICE_FAILED_TO_RESPOND = 0xB, /// 0xB
}

private version (modbus_use_prealloc_exceptions)
{
    __gshared
    {
        auto preallocModbusException = new ModbusException("many args");
        auto preallocModbusTimeoutException = new ModbusTimeoutException("many args", Duration.init);
        auto preallocCheckFailException = new CheckFailException(0, 0);
        auto preallocReadDataLengthException = new ReadDataLengthException(0,0,0,0);
        auto preallocFunctionErrorException = new FunctionErrorException(0,0,0,0);
        auto preallocSlaveFuncProcessException = new SlaveFuncProcessException(0, 0, FunctionErrorCode.SLAVE_DEVICE_FAILURE);
    }
}

/// Returns: preallocated exception with new values of fields
ModbusException modbusException()(string msg, string file=__FILE__, size_t line=__LINE__)
{
    version (modbus_use_prealloc_exceptions)
    {
        preallocModbusException.msg = msg;
        preallocModbusException.file = file;
        preallocModbusException.line = line;
        return preallocModbusException;
    }
    else return new ModbusException(msg, file, line);
}

/// Returns: preallocated exception with new values of fields
ModbusTimeoutException modbusTimeoutException()(string msg, ulong dev, ubyte fnc, Duration dur, string file=__FILE__, size_t line=__LINE__)
{
    version (modbus_use_prealloc_exceptions)
    {
        preallocModbusTimeoutException.msg = msg;
        preallocModbusTimeoutException.dev = dev;
        preallocModbusTimeoutException.fnc = fnc;
        preallocModbusTimeoutException.dur = dur;
        preallocModbusTimeoutException.file = file;
        preallocModbusTimeoutException.line = line;
        return preallocModbusTimeoutException;
    }
    else return new ModbusTimeoutException(msg, dev, fnc, dur, file, line);
}

/// Returns: preallocated exception with new values of fields
CheckFailException checkFailException()(ulong dev, ubyte fnc,
                                    string file=__FILE__, size_t line=__LINE__)
{
    version (modbus_use_prealloc_exceptions)
    {
        preallocCheckFailException.msg = "check CRC fails";
        preallocCheckFailException.dev = dev;
        preallocCheckFailException.fnc = fnc;
        preallocCheckFailException.file = file;
        preallocCheckFailException.line = line;
        return preallocCheckFailException;
    }
    else return new CheckFailException(dev, fnc, file, line);
}

/// Returns: preallocated exception with new values of fields
FunctionErrorException functionErrorException()(ulong dev, ubyte fnc, ubyte res, ubyte code,
                                                string file=__FILE__, size_t line=__LINE__)
{
    version (modbus_use_prealloc_exceptions)
    {
        preallocFunctionErrorException.msg = "error while read function response";
        preallocFunctionErrorException.dev = dev;
        preallocFunctionErrorException.fnc = fnc;
        preallocFunctionErrorException.res = res;
        preallocFunctionErrorException.code = cast(FunctionErrorCode)code;
        preallocFunctionErrorException.file = file;
        preallocFunctionErrorException.line = line;
        return preallocFunctionErrorException;
    }
    else return new FunctionErrorException(dev, fnc, res, code, file, line);
}

/// Returns: preallocated exception with new values of fields
ReadDataLengthException readDataLengthException()(ulong dev, ubyte fnc, size_t exp, size_t res,
                                                string file=__FILE__, size_t line=__LINE__)
{
    version (modbus_use_prealloc_exceptions)
    {
        preallocReadDataLengthException.msg = "error while read function response: wrong length";
        preallocReadDataLengthException.dev = dev;
        preallocReadDataLengthException.fnc = fnc;
        preallocReadDataLengthException.expected = exp;
        preallocReadDataLengthException.responseLength = res;
        preallocReadDataLengthException.file = file;
        preallocReadDataLengthException.line = line;
        return preallocReadDataLengthException;
    }
    else return new ReadDataLengthException(dev, fnc, exp, res, file, line);
}

SlaveFuncProcessException slaveFuncProcessException()(ulong dev, ubyte fnc, FunctionErrorCode code)
{
    version (modbus_use_prealloc_exceptions)
    {
        preallocSlaveFuncProcessException.dev = dev;
        preallocSlaveFuncProcessException.fnc = fnc;
        preallocSlaveFuncProcessException.code = code;
        return preallocSlaveFuncProcessException;
    }
    else return new SlaveFuncProcessException(dev, fnc, code);
}