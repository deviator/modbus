///
module modbus.connection.base;

public import serialport.exception;

static import serialport.base;

public import std.datetime : Duration;

/// Connection
interface Connection
{
    @property
    {
        ///
        Duration readTimeout();
        ///
        Duration writeTimeout();
        ///
        void readTimeout(Duration);
        ///
        void writeTimeout(Duration);
    }

    alias CanRead = serialport.base.SerialPort.CanRead;

    /++ Write data to connection

        Returns:
            writed data length
     +/
    void write(const(void)[] data);

    /++ Read data from connection

        Params:
            buffer = preallocated buffer for reading

        Returns:
            slice of buffer with readed data
     +/
    void[] read(void[] buffer, CanRead cr=CanRead.allOrNothing);
}

///
abstract class AbstractConnection : Connection
{
    import std.datetime : msecs;
protected:
    Duration _rtm = 10.msecs, _wtm = 10.msecs;

public:

    @property override
    {
        Duration readTimeout() { return _rtm; }
        Duration writeTimeout() { return _wtm; }
        void readTimeout(Duration d) { _rtm = d; }
        void writeTimeout(Duration d) { _wtm = d; }
    }

    abstract void write(const(void)[] data);
    abstract void[] read(void[] buffer, CanRead cr=CanRead.allOrNothing);
}

version (unittest)
{
    import std.exception : assertThrown, assertNotThrown, enforce;
    import std.stdio;
    import core.thread;
    import std.datetime.stopwatch;
    import std.array;
    import std.format;
}

Connection nullConnection()
{
    return new class Connection
    {
    override:
        @property
        {
            Duration readTimeout() { return Duration.zero; }
            Duration writeTimeout() { return Duration.zero; }
            void readTimeout(Duration) {}
            void writeTimeout(Duration) {}
        }
        void write(const(void)[] data) { }
        void[] read(void[] b, CanRead cr=CanRead.allOrNothing) { return b[0..0]; }
    };
}

import modbus.cbuffer;

/++ Circle buffer, for fibers only
 +/
class VirtualConnection : AbstractConnection
{
    import std.datetime.stopwatch;
    import core.thread : Fiber;
    import serialport.exception : TimeoutException;
    import std.exception : enforce;
    import std.algorithm : min;
    import std.stdio;

    string name;

    CBufferCls rx, tx;

    this(CBufferCls rx, CBufferCls tx, string name)
    {
        this.name = name;
        this.rx = rx;
        this.tx = tx;
    }

override:

    void write(const(void)[] data)
    {
        auto sw = StopWatch(AutoStart.yes);
        auto fb = enforce(Fiber.getThis, "must run in fiber");

        auto udat = cast(ubyte[])data;

        foreach (i; 0 .. data.length)
        {

            while (tx.full)
            {
                fb.yield();
                if (sw.peek > _wtm)
                    throwTimeoutException(name, "write timeout");
            }
            tx.put(udat[i]);
        }
    }

    void[] read(void[] ext, CanRead cr=CanRead.allOrNothing)
    {
        auto sw = StopWatch(AutoStart.yes);
        auto fb = enforce(Fiber.getThis, "must run in fiber");

        auto uret = cast(ubyte[])ext;

        foreach (i; 0 .. uret.length)
        {
            while (rx.empty)
            {
                if (sw.peek > _rtm)
                {
                    if (cr == CanRead.allOrNothing)
                        throwTimeoutException(name, "read timeout");
                    else if (cr == CanRead.anyNonZero)
                    {
                        if (i != 0) return ext[0..i];
                        throwTimeoutException(name, "read timeout");
                    }
                    else return ext[0..i];
                }
                fb.yield();
            }
            uret[i] = rx.front;
            rx.popFront;
        }
        return ext[];
    }
}

unittest
{
    auto cb = new CBufferCls(40);

    auto c = new VirtualConnection(cb, cb, "test");

    void fnc()
    {
        enum data = "1qazxsw23edcv";
        void[128] tmp = void;
        foreach (i; 0 .. 2000)
        {
            c.write(data);
            auto r = cast(string)c.read(tmp[0..data.length]).idup;
            assert(data == r);
        }
    }

    auto f = new Fiber(&fnc);

    auto sw = StopWatch(AutoStart.yes);
    while (f.state != Fiber.State.TERM)
    {
        f.call;
        Thread.sleep(1.msecs);
    }
}

///
VirtualConnection[2] virtualPipeConnection(size_t bufSize, string prefix)
{
    auto a = new CBufferCls(bufSize);
    auto b = new CBufferCls(bufSize);
    return [new VirtualConnection(a, b, prefix ~ "A"),
            new VirtualConnection(b, a, prefix ~ "B")];
}

unittest
{
    enum data = "1qazxsw23edcv";
    void[data.length] buf = void;

    auto cc = virtualPipeConnection(77, "test");

    void fncA()
    {
        foreach (i; 0 .. 200)
        {
            cc[0].write(data);
            Fiber.yield();
        }
    }

    void fncB()
    {
        foreach (i; 0 .. 100)
        {
            auto r = cast(string)cc[1].read(buf).idup;
            assert(data == r);
            Fiber.yield();
        }

        foreach (i; 0 .. 100)
        {
            enum k = 5;
            auto r = cast(string)cc[1].read(buf[0..k]).idup;
            assert(data[0..k] == r);
            r = cast(string)cc[1].read(buf[k..data.length]).idup;
            assert(data[k..$] == r);
            Fiber.yield();
        }
    }

    auto f1 = new Fiber(&fncA);
    auto f2 = new Fiber(&fncB);

    auto sw = StopWatch(AutoStart.yes);

    while (f1.state != Fiber.State.TERM &&
           f2.state != Fiber.State.TERM &&
           sw.peek < 500.msecs)
    {
        f1.call;
        f2.call;
        Thread.sleep(1.msecs);
    }

    assertThrown( (){ foreach (i; 0 .. 100) cc[0].write(data); }());
    assertThrown( (){ foreach (i; 0 .. 100) cc[1].read(buf); }());
}