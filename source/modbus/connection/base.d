///
module modbus.connection.base;

public import std.datetime : Duration;

/// Connection for backends
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
    void[] read(void[] buffer);
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
            ///
            Duration readTimeout() { return Duration.zero; }
            ///
            Duration writeTimeout() { return Duration.zero; }
            ///
            void readTimeout(Duration) {}
            ///
            void writeTimeout(Duration) {}
        }
        void write(const(void)[] data) { }
        void[] read(void[] buffer) { return buffer[0..0]; }
    };
}

class FTCon : Connection
{
    import std.datetime.stopwatch;
    import core.thread : Fiber;
    import serialport.exception : TimeoutException;
    import std.exception : enforce;
    import std.algorithm : min;

    import std.stdio;

    string name;

    Duration _rtm = 10.msecs, _wtm = 10.msecs;

    void[] buffer;

    size_t start() @property { return *_start; }
    size_t end() @property { return *_end; }
    size_t* _start, _end;

    this(void[] buffer, size_t* start, size_t* end, string name)
    {
        this.buffer = buffer;
        this.name = name;
        this._start = start;
        this._end = end;
    }

    invariant
    {
        assert(*_start < buffer.length);
        assert(*_end < buffer.length);
    }

override:
    @property
    {
        Duration readTimeout() { return _rtm; }
        Duration writeTimeout() { return _wtm; }
        void readTimeout(Duration d) { _rtm = d; }
        void writeTimeout(Duration d) { _wtm = d; }
    }

    void write(const(void)[] data)
    {
        auto sw = StopWatch(AutoStart.yes);
        auto fb = enforce(Fiber.getThis, "must run in fiber");

        auto ubuf = cast(ubyte[])buffer;
        auto udat = cast(ubyte[])data;

        size_t n;
        const bl = buffer.length;
        foreach (i; 0 .. data.length)
        {
            n = (end + i) % bl;
            while (n == start-1)
            {
                fb.yield();
                if (sw.peek > _wtm)
                    throw new TimeoutException(name);
            }
            ubuf[n] = udat[i];
        }
        *_end = (n+1) % bl;
        return;
    }

    void[] read(void[] ret)
    {
        auto sw = StopWatch(AutoStart.yes);
        auto fb = enforce(Fiber.getThis, "must run in fiber");

        auto uret = cast(ubyte[])ret;
        auto ubuf = cast(ubyte[])buffer;

        size_t n = start;
        const bl = buffer.length;
        foreach (i; 0 .. ret.length)
        {
            while (n == end)
            {
                if (sw.peek > _rtm)
                    throw new TimeoutException(name);
                fb.yield();
            }
            n = (start + i) % bl;
            uret[i] = ubuf[n];
        }
        *_start = (n+1) % bl;
        return ret[];
    }
}

unittest
{
    void[13*3+1] buffer = void;
    size_t start, end;

    auto gba = appender!(char[]);
    string getBuffer()
    {
        auto buf = cast(char[])buffer;
        auto s = start;
        auto e = end;
        gba.clear();
        formattedWrite(gba, "%2d-%2d ", s, e);
        foreach (i; 0 .. buf.length)
        {
            auto ch = buf[i];
            if (s < e) gba.put(s <= i && i < e ? ch : '-');
            else if (s == e) gba.put('-');
            else       gba.put(s <= i || i < e ? ch : '-');
        }
        return gba.data().idup;
    }

    auto c = new FTCon(buffer, &start, &end, "test");

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

Connection[2] fiberTestConnection(size_t bufSize, string prefix)
{
    void[] buf = new void[](bufSize);
    auto p = new size_t[](2);
    return [new FTCon(buf, &p[0], &p[1], prefix ~ "A"),
            new FTCon(buf, &p[0], &p[1], prefix ~ "B")];
}

unittest
{
    enum data = "1qazxsw23edcv";
    void[data.length] buf = void;

    auto cc = fiberTestConnection(77, "test");

    import std.array;

    auto gba = appender!(char[]);

    string getBuffer()
    {
        auto ftcon = enforce(cast(FTCon)cc[0]);
        auto buf = cast(char[])ftcon.buffer;
        auto s = ftcon.start;
        auto e = ftcon.end;
        gba.clear();
        formattedWrite(gba, "%2d-%2d ", s, e);
        foreach (i; 0 .. buf.length)
        {
            auto ch = buf[i];
            if (s < e) gba.put(s <= i && i < e ? ch : '-');
            else if (s == e) gba.put('-');
            else       gba.put(s <= i || i < e ? ch : '-');
        }
        return gba.data().idup;
    }

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