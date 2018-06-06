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
import modbus.msleep;

///
abstract class TcpConnectionBase : AbstractConnection
{
protected:
    Socket sock;

    void delegate(Duration) sleepFunc;

    void sleep(Duration d)
    {
        if (sleepFunc !is null) sleepFunc(d);
        else msleep(d);
    }

    Duration _writeStepSleep = 10.usecs;
    Duration _readStepSleep = 10.usecs;

    import core.stdc.errno;

    void m_write(const(void)[] buf)
    {
        sock.blocking = false;
        size_t written;
        const sw = StopWatch(AutoStart.yes);
        while (sw.peek < _wtm)
        {
            auto res = sock.send(buf[written..$]);
            if (res == 0) // connection is closed
                throwCloseTcpConnection("write");
            if (res == Socket.ERROR)
            {
                if (wouldHaveBlocked) res = 0;
                else throwModbusException("TCP Socket send error " ~ sock.getErrorText);
            }
            written += res;
            if (written == buf.length) return;
            this.sleep(_writeStepSleep);
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
            if (res == 0) // connection is closed
                throwCloseTcpConnection("read");
            if (res == Socket.ERROR)
            {
                if (wouldHaveBlocked) res = 0;
                else throwModbusException("TCP Socket receive error " ~ sock.getErrorText);
            }
            readed += res;
            if (readed == buf.length) return buf[];
            this.sleep(_readStepSleep);
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
    this(Socket s, void delegate(Duration) sf=null)
    {
        if (s is null)
            throwModbusException("TCP Socket is null");
        sleepFunc = sf;
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
    bool terminate, inf;

    this(Socket sock, size_t id, size_t dlen, bool inf=false)
    {
        this.id = id;
        this.inf = inf;
        con = new SlaveTcpConnection(sock);
        data = new void[](dlen);
        con.readTimeout = 1.seconds;
        super(&run);
    }

    void run()
    {
        testPrintf!("slave #%d start read")(id);
        while (result.length < data.length || inf)
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
    bool inf;

    this(Address addr, int cc, size_t dlen, bool inf=false)
    {
        this.dlen = dlen;
        this.inf = inf;
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
                cons ~= new CFCSlave(serv.accept(), cons.length, dlen, inf);
                testPrintf!"new client, create slave #%d"(cons.length-1);
                yield();
            }

            foreach (c; cons.filter!(a=>a.state != a.State.TERM && !a.terminate))
            {
                try c.call;
                catch (CloseTcpConnection)
                {
                    testPrintf!"close slave #%d connection (%d bytes received)"(c.id, c.result.length);
                    c.con.socket.shutdown(SocketShutdown.BOTH);
                    c.con.socket.close();
                    c.terminate = true;
                }
                c.con.sleep(uniform(1,5).msecs);
            }

            if (cons.length && cons.all!(a=>a.state == a.State.TERM || a.terminate))
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
    bool noread;

    void[] data;

    this(Address addr, size_t id, size_t dlen, bool noread=false)
    {
        this.id = id;
        this.noread = noread;
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

        if (noread)
        {
            testPrintf!"close master #%d connection"(id);
            con.socket.shutdown(SocketShutdown.BOTH);
            con.socket.close();
        }
        else
        {
            void[24] tmp = void;
            testPrintf!"master #%d start receive"(id);
            serv_id = (cast(size_t[])con.read(tmp[], con.CanRead.anyNonZero))[0];
            testPrintf!"master #%d receive serv id #%d"(id, serv_id);
        }
    }
}

unittest
{
    mixin(mainTestMix);
    ut!simpleFiberTest(new InternetAddress("127.0.0.1", 8091));
    ut!closeSocketTest(new InternetAddress("127.0.0.1", 8092));
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

void closeSocketTest(Address addr)
{
    enum BS = 512;
    enum N = 12;
    auto cfs = new CFSlave(addr, N, BS, true);
    scope(exit) cfs.serv.close();
    CFMaster[] cfm;
    foreach (i; 0 .. N)
        cfm ~= new CFMaster(addr, i, BS, true);

    bool work = true;
    while (work)
    {
        alias TERM = Fiber.State.TERM;
        if (cfs.state != TERM) cfs.call;
        foreach (c; cfm.filter!(a=>a.state != TERM)) c.call;

        Thread.sleep(5.msecs);
        if (cfm.all!(a=>a.state == TERM) && cfs.state == TERM)
        {
            work = false;
            assert(cfs.cons.all!(a=>a.terminate));
            assert(cfs.cons.all!(a=>a.result.length == BS));
        }
    }
}