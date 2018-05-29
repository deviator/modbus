///
module modbus.protocol.base;

public import std.bitmanip : BitArray;
public import std.exception : enforce;
public import std.datetime.stopwatch;
public import std.conv : to;

version (modbus_verbose)
    public import std.experimental.logger;

public import modbus.exception;
public import modbus.connection;
public import modbus.backend;
public import modbus.types;
public import modbus.func;

///
abstract class Modbus
{
protected:
    void[MAX_BUFFER] buffer;

    Backend be;
    Connection con;
public:

    ///
    this(Backend be, Connection con)
    {
        if (be is null) throwModbusException("backend is null");
        if (con is null) throwModbusException("connection is null");
        this.be = be;
        this.con = con;
    }

    ///
    Backend backend() @property { return be; }
    ///
    Connection connection() @property { return con; }

    /++ Write to serial port

        Params:
            dev = modbus device address (number)
            fnc = function number
            args = writed data in native endian
        Returns:
            sended message
     +/
    const(void)[] write(Args...)(ulong dev, ubyte fnc, Args args)
    {
        auto buf = be.buildMessage(buffer, dev, fnc, args);
        con.write(buf);
        return buf;
    }
}