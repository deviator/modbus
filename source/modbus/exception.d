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

private __gshared preallocModbusException = new ModbusException("many args");

/// Returns: preallocated exception with new values of fields
ModbusException modbusException(string msg, string file=__FILE__, size_t line=__LINE__) @nogc
{
    preallocModbusException.msg = msg;
    preallocModbusException.file = file;
    preallocModbusException.line = line;
    return preallocModbusException;
}

///
class ModbusDevException : ModbusException
{
    ///
    ubyte dev, fnc;
    ///
    this(ubyte dev, ubyte fnc, string msg, string file=__FILE__, size_t line=__LINE__)
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
    this(ubyte dev, ubyte fnc, string file=__FILE__, size_t line=__LINE__)
    {
        super(dev, fnc, format("dev %d fnc %d(0x%x) recive msg CRC check fails",
                    dev, fnc, fnc), file, line);
    }
}

private __gshared preallocCheckCRCException = new CheckCRCException(0, 0);

/// Returns: preallocated exception with new values of fields
CheckCRCException checkCRCException(ubyte dev, ubyte fnc,
                                    string file=__FILE__, size_t line=__LINE__) @nogc
{
    preallocCheckCRCException.msg = "check CRC fails";
    preallocCheckCRCException.dev = dev;
    preallocCheckCRCException.fnc = fnc;
    preallocCheckCRCException.file = file;
    preallocCheckCRCException.line = line;

    return preallocCheckCRCException;
}

///
class FunctionErrorException : ModbusDevException
{
    ///
    ubyte res;
    ///
    FunctionErrorCode code;

    ///
    this(ubyte dev, ubyte fnc, ubyte res, ubyte code,
            string file=__FILE__, size_t line=__LINE__)
    {
        this.res = res;
        this.code = cast(FunctionErrorCode)code;

        super(dev, fnc, format("dev %d fnc %d(0x%x) recive fnc %d(0x%x) with exception code %s (%d)",
        dev, fnc, fnc, res, res, code, code), file, line);
    }
}

private __gshared preallocFunctionErrorException = new FunctionErrorException(0,0,0,0);

/// Returns: preallocated exception with new values of fields
FunctionErrorException functionErrorException(ubyte dev, ubyte fnc, ubyte res, ubyte code,
                                              string file=__FILE__, size_t line=__LINE__) @nogc
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

///
class ReadDataLengthException : ModbusDevException
{
    size_t expected, responseLength;
    ///
    this(ubyte dev, ubyte fnc, size_t exp, size_t res,
            string file=__FILE__, size_t line=__LINE__)
    {
        expected = exp;
        responseLength = res;
        super(dev, fnc, format("dev %d fnc to %d(0x%x) recieves wrong"~
                    " count of bytes (%d != expected %d or more what %d)",
                    dev, fnc, fnc, res, exp, MINIMUM_MODBUS_MSG_LENGTH), file, line);
    }
}

private __gshared preallocReadDataLengthException = new ReadDataLengthException(0,0,0,0);

/// Returns: preallocated exception with new values of fields
ReadDataLengthException readDataLengthException(ubyte dev, ubyte fnc, size_t exp, size_t res,
                                                string file=__FILE__, size_t line=__LINE__) @nogc
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