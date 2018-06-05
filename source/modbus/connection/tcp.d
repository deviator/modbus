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
    Socket sock;

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
                do f.yield(); while (sw.peek < d);
            }
            else Thread.sleep(d);
        }
    }

    import core.stdc.errno;

    void m_write(const(void)[] buf)
    {
        sock.blocking = false;
        size_t written;
        const sw = StopWatch(AutoStart.yes);
        while (sw.peek < _wtm)
        {
            auto res = sock.send(buf[written..$]);
            if (res == Socket.ERROR)
            {
                if (wouldHaveBlocked) res = 0;
                else throwModbusException("TCP Socket send error " ~ sock.getErrorText);
            }
            written += res;
            if (written == buf.length) return;
            this.sleep(10.usecs);
        }
        throwTimeoutException(sock.to!string, "write timeout");
    }

    void[] m_read(void[] buf, CanRead cr)
    {
        sock.blocking = false;
        size_t readed;
        const sw = StopWatch(AutoStart.yes);
        auto ss = new SocketSet;
        ss.add(sock);
        while (sw.peek < _rtm)
        {
            auto res = sock.receive(buf[readed..$]);
            if (res == Socket.ERROR)
            {
                if (wouldHaveBlocked) res = 0;
                else throwModbusException("TCP Socket receive error " ~ sock.getErrorText);
            }
            readed += res;
            if (readed == buf.length) return buf[];
            this.sleep(10.usecs);
        }
        if (cr == CanRead.allOrNothing || (cr == CanRead.anyNonZero && !readed))
            throwTimeoutException(sock.to!string, "read timeout");
        return buf[0..readed];
    }

public:

    ///
    inout(Socket) socket() inout @property { return sock; }
}

/// Client
class MasterTcpConnection : TcpConnectionBase
{
protected:
    Address addr;

public:

    ///
    this(Address addr, void delegate(Duration) sleepFunc=null)
    {
        this.addr = addr;
        this.sleepFunc = sleepFunc;
    }

    protected bool haltSock()
    {
        if (sock is null) return false;
        sock.shutdown(SocketShutdown.BOTH);
        sock.close();
        sock = null;
        return true;
    }

    protected void initSock()
    {
        sock = new TcpSocket();
        sock.blocking = true;
        sock.connect(addr);
        sock.blocking = false;
    }

override:

    void write(const(void)[] msg)
    {
        if (sock is null) initSock();
        m_write(msg);
    }

    void[] read(void[] buf, CanRead cr=CanRead.allOrNothing)
    {
        if (sock is null) initSock();
        return m_read(buf, cr);
    }

    void reconnect()
    {
        haltSock();
        initSock();
    }
}

/// slave connection
class SlaveTcpConnection : TcpConnectionBase
{
    ///
    this(Socket s)
    {
        if (s is null)
            throwModbusException("TCP Socket is null");
        sock = s;
        sock.blocking = false;
    }

override:
    void write(const(void)[] msg) { m_write(msg); }

    void[] read(void[] buf, CanRead cr=CanRead.allOrNothing)
    { return m_read(buf, cr); }

    void reconnect() { assert(0, "not allowed for SlaveTcpConnection"); }
}

version (unittest): package(modbus):

import modbus.ut;

class CFCSlave : Fiber
{
    SlaveTcpConnection con;

    void[] result, data;
    size_t id;

    this(Socket sock, size_t id, size_t dlen)
    {
        this.id = id;
        con = new SlaveTcpConnection(sock);
        data = new void[](dlen);
        con.readTimeout = 1.seconds;
        super(&run);
    }

    void run()
    {
        testPrintf!("slave #%d start read")(id);
        while (result.length < data.length)
            result ~= con.read(data, con.CanRead.zero);
        testPrintf!("slave #%d finish read (%d)")(id, result.length);

        con.sleep(uniform(1, 20).msecs);
        con.write([id]);
        testPrintf!("slave #%d finish")(id);
    }
}

class CFSlave : Fiber
{
    TcpSocket serv;
    CFCSlave[] cons;
    size_t dlen;
    SocketSet ss;

    this(Address addr, int cc, size_t dlen)
    {
        this.dlen = dlen;
        serv = new TcpSocket;
        serv.blocking = true;
        serv.bind(addr);
        serv.listen(cc);
        serv.blocking = false;
        ss = new SocketSet;
        super(&run);
    }

    void run()
    {
        while (true)
        {
            scope (exit) yield();
            ss.reset();
            ss.add(serv);

            while (Socket.select(ss, null, null, Duration.zero))
            {
                cons ~= new CFCSlave(serv.accept(), cons.length, dlen);
                testPrintf!"new client, create slave #%d"(cons.length-1);
                yield();
            }

            foreach (c; cons.filter!(a=>a.state != a.State.TERM))
            {
                c.call;
                c.con.sleep(uniform(1,5).msecs);
            }

            if (cons.length && cons.all!(a=>a.state == a.State.TERM))
            {
                testPrint("server finished");
                break;
            }
        }
    }
}

class CFMaster : Fiber
{
    MasterTcpConnection con;
    size_t id;
    size_t serv_id;

    void[] data;

    this(Address addr, size_t id, size_t dlen)
    {
        this.id = id;
        con = new MasterTcpConnection(addr);
        data = new void[](dlen);
        foreach (ref v; cast(ubyte[])data)
            v = uniform(ubyte(0), ubyte(128));
        super(&run);
    }

    void run()
    {
        con.sleep(uniform(1, 50).msecs);
        con.write(data);
        testPrintf!"master #%d send data"(id);
        con.readTimeout = 2000.msecs;
        con.sleep(uniform(1, 50).msecs);
        void[24] tmp = void;
        testPrintf!"master #%d start receive"(id);
        serv_id = (cast(size_t[])con.read(tmp[], con.CanRead.anyNonZero))[0];
        testPrintf!"master #%d receive serv id #%d"(id, serv_id);
    }
}

unittest
{
    mixin(mainTestMix);
    ut!simpleFiberTest(new InternetAddress("127.0.0.1", 8091));
}

void simpleFiberTest(Address addr)
{
    enum BS = 512;
    enum N = 12;
    auto cfs = new CFSlave(addr, N, BS);
    scope(exit) cfs.serv.close();
    CFMaster[] cfm;
    foreach (i; 0 .. N)
        cfm ~= new CFMaster(addr, i, BS);
    scope(exit) cfm.each!(a=>a.con.sock.close());

    bool work = true;
    int step;
    while (work)
    {
        alias TERM = Fiber.State.TERM;
        if (cfs.state != TERM) cfs.call;
        foreach (c; cfm.filter!(a=>a.state != TERM)) c.call;

        step++;
        Thread.sleep(5.msecs);
        if (cfm.all!(a=>a.state == TERM) && cfs.state == TERM)
        {
            enforce(cfs.cons.length == N, "no server connections");
            foreach (i; 0 .. N)
            {
                auto mm = cfm[i];
                auto id = mm.serv_id;
                auto ss = cfs.cons[id];
                if (ss.result.length == mm.data.length)
                {
                    enforce(equal(cast(ubyte[])ss.result, cast(ubyte[])mm.data));
                    work = false;
                }
                else throw new Exception(text(ss.result, " != ", mm.data));
            }
            testPrintf!"basic loop steps: %s"(step);
        }
    }
}