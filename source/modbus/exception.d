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

class ReadDataLengthException : ModbusDevException
{
    ///
    this(ubyte dev, ubyte fnc, size_t exp, size_t res,
            string file=__FILE__, size_t line=__LINE__)
    {
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