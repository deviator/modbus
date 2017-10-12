///
module modbus.protocol.base;

public import std.bitmanip : BitArray;
public import std.exception : enforce;
public import std.datetime;
public import std.conv : to;

version (modbus_verbose)
    public import std.experimental.logger;

public import modbus.exception;
public import modbus.connection;
public import modbus.backend;
public import modbus.types;
public import modbus.func;

package enum MAX_BUFFER = 260;

///
class Modbus
{
protected:
    void[MAX_BUFFER] buffer;

    Connection con;
    Backend be;

    void delegate(Duration) sleepFunc;

    void sleep(Duration dur)
    {
        import core.thread;

        if (sleepFunc !is null) sleepFunc(dur);
        else
        {
            if (auto fiber = Fiber.getThis)
            {
                auto dt = StopWatch(AutoStart.yes);
                while (dt.peek.to!Duration < dur)
                    fiber.yield();
            }
            else Thread.sleep(dur);
        }
    }

    ///
    Duration writeStepPause() @property
    { return (cast(ulong)(1e7 * 10 / 9600.0)).hnsecs; }

public:

    ///
    this(Connection con, Backend be, void delegate(Duration) sf=null)
    {
        this.con = enforce(con, modbusException("connection is null"));
        this.be = enforce(be, modbusException("backend is null"));
        this.sleepFunc = sf;
    }

    ///
    Duration writeTimeout=10.msecs;
    /// time for waiting message
    Duration readTimeout=1.seconds;

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

        size_t cnt = con.write(buf);
        if (cnt == buf.length) return buf;

        auto dt = StopWatch(AutoStart.yes);
        while (cnt != buf.length)
        {
            cnt += con.write(buf[cnt..$]);
            this.sleep(writeStepPause);
            if (dt.peek.to!Duration > writeTimeout)
                throw modbusTimeoutException("write", dev, fnc, writeTimeout);
        }

        return buf;
    }
}