///
module modbus.exception;

import std.string : format;

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
class ModbusDevException : ModbusException
{
    ///
    ulong dev;
    ///
    ubyte fnc;
    ///
    this(ulong dev, ubyte fnc, string msg, string file=__FILE__, size_t line=__LINE__)
    {
        this.dev = dev;
        this.fnc = fnc;
        super(msg, file, line);
    }
}

///
class CheckCRCException : ModbusDevException
{
    ///
    this(ulong dev, ubyte fnc, string file=__FILE__, size_t line=__LINE__)
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

        super(dev, fnc, format("dev %d fnc %d(0x%x) recive fnc %d(0x%x) with exception code %s (%d)",
        dev, fnc, fnc, res, res, cast(FunctionErrorCode)code, code), file, line);
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
        auto preallocCheckCRCException = new CheckCRCException(0, 0);
        auto preallocReadDataLengthException = new ReadDataLengthException(0,0,0,0);
        auto preallocFunctionErrorException = new FunctionErrorException(0,0,0,0);
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
CheckCRCException checkCRCException()(ulong dev, ubyte fnc,
                                    string file=__FILE__, size_t line=__LINE__)
{
    version (modbus_use_prealloc_exceptions)
    {
        preallocCheckCRCException.msg = "check CRC fails";
        preallocCheckCRCException.dev = dev;
        preallocCheckCRCException.fnc = fnc;
        preallocCheckCRCException.file = file;
        preallocCheckCRCException.line = line;
        return preallocCheckCRCException;
    }
    else return new CheckCRCException(dev, fnc, file, line);
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