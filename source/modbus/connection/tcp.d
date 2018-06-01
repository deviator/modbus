///
module modbus.connection.tcp;

import std.conv : to;
import std.datetime.stopwatch;
import std.exception : enforce;
import std.socket;
public import std.socket : Address, InternetAddress, Internet6Address;
version (Posix) public import std.socket : UnixAddress;

import modbus.exception;
import modbus.connection.base;

///
abstract class TcpConnectionBase : AbstractConnection
{
protected:
    TcpSocket _socket;

    void delegate(Duration) sleepFunc;

    void sleep(Duration d)
    {
        import core.thread : Fiber, Thread;

        if (sleepFunc !is null) sleepFunc(d);
        else
        {
            if (auto f = Fiber.getThis)
            {
                const sw = StopWatch(AutoStart.yes);
                while (sw.peek < d) f.yield();
            }
            else Thread.sleep(d);
        }
    }

    ptrdiff_t m_write(Socket s, const(void)[] buf)
    {
        const res = s.send(buf);
        if (res == Socket.ERROR)
            throwModbusException("error while send data to tcp socket");
        return res;
    }

    void l_write(Socket s, const(void)[] buf)
    {
        size_t written;
        const sw = StopWatch(AutoStart.yes);
        while (sw.peek < _wtm)
        {
            written += m_write(s, buf[written..$]);
            if (written == buf.length) return;
            this.sleep(1.msecs);
        }
        throwTimeoutException(s.to!string, "write timeout");
    }

    void[] m_read(Socket s, void[] buf)
    {
        s.blocking = false;
        const res = s.receive(buf);
        if (res == Socket.ERROR) return buf[0..0];
        return buf[0..res];
    }

    void[] l_read(Socket s, void[] buf, CanRead cr)
    {
        size_t readed;
        const sw = StopWatch(AutoStart.yes);
        while (sw.peek < _rtm)
        {
            // can block if timeout not expires, but not full data received
            readed += m_read(s, buf[readed..$]).length;
            if (readed == buf.length) return buf[];
            this.sleep(1.msecs);
        }
        if (cr == CanRead.allOrNothing || (cr == CanRead.anyNonZero && !readed))
            throwTimeoutException(s.to!string, "read timeout");
        return buf[0..readed];
    }

public:

    ///
    inout(TcpSocket) socket() inout @property { return _socket; }
}

/// Client
class MasterTcpConnection : TcpConnectionBase
{
    ///
    this(Address addr, void delegate(Duration) sleepFunc=null)
    {
        _socket = new TcpSocket();

        this.sleepFunc = sleepFunc;

        _socket.blocking = true;
        _socket.connect(addr);
        _socket.blocking = false;
    }

override:

    void write(const(void)[] msg) { l_write(_socket, msg); }

    void[] read(void[] buf, CanRead cr=CanRead.allOrNothing)
    { return l_read(_socket, buf, cr); }
}

/// Server
class SlaveTcpConnection : TcpConnectionBase
{
    Socket cli;

    ///
    this(Address addr, void delegate(Duration) sleepFunc=null)
    {
        _socket = new TcpSocket();

        this.sleepFunc = sleepFunc;

        _socket.blocking = true;
        _socket.bind(addr);
        _socket.listen(1);
        _socket.blocking = false;
    }

override:
    void write(const(void)[] msg)
    {
        if (cli is null)
            throwModbusException("no client connected");

        l_write(cli, msg);
    }

    void[] read(void[] buf, CanRead cr=CanRead.allOrNothing)
    {
        if (cli is null)
        {
            try cli = socket.accept();
            catch (Exception e)
            {
                if (cr == CanRead.zero) return buf[0..0];
                else throw e;
            }
        }
        enforce(cli, "cli is null, but accepted from socket");
        return l_read(cli, buf, cr);
    }
}

version (unittest): package(modbus):

import modbus.ut;

class CFSlave : Fiber
{
    SlaveTcpConnection con;

    void[] result, data;

    this(Address addr, size_t dlen)
    {
        con = new SlaveTcpConnection(addr);
        data = new void[](dlen);
        con.readTimeout = 1.seconds;
        super(&run);
    }

    void run()
    {
        testPrint("slave start read");
        while (result.length < data.length)
            result ~= con.read(data, con.CanRead.zero);
        testPrintf!("slave finish read (%d)")(result.length);

        con.write("buffer filled");
    }
}

class CFMaster : Fiber
{
    MasterTcpConnection con;

    void[] data;

    this(Address addr, size_t dlen)
    {
        con = new MasterTcpConnection(addr);
        data = new void[](dlen);
        foreach (ref v; cast(ubyte[])data)
            v = uniform(ubyte(0), ubyte(128));
        super(&run);
    }

    void run()
    {
        testPrint("master start write");
        con.write(data);
        testPrint("master finish write");

        con.readTimeout = 1.seconds;

        void[24] tmp = void;
        auto ret = con.read(tmp[], con.CanRead.anyNonZero);
        testPrint("master receive: "~cast(string)ret);
    }
}

unittest
{
    mixin(mainTestMix);
    ut!simpleFiberTest(new InternetAddress("127.0.0.1", 8090));
}

void simpleFiberTest(Address addr)
{
    enum BS = 512;
    auto cfs = new CFSlave (addr, BS);
    scope(exit) cfs.con._socket.close();
    auto cfm = new CFMaster(addr, BS);
    scope(exit) cfm.con._socket.close();

    bool work = true;
    int step;
    while (work)
    {
        alias TERM = Fiber.State.TERM;
        if (cfs.state != TERM) cfs.call;
        if (cfm.state != TERM) cfm.call;

        step++;
        Thread.sleep(30.msecs);
        if (cfm.state == TERM && cfs.state == TERM)
        {
            if (cfs.result.length == cfm.data.length)
            {
                enforce(equal(cast(ubyte[])cfs.result, cast(ubyte[])cfm.data));
                work = false;
                testPrintf!"basic loop steps: %s"(step);
            }
            else throw new Exception(text(cfs.result, " != ", cfm.data));
        }
    }
}