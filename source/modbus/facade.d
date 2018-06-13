/// modbus with back end
module modbus.facade;

import modbus.backend;
import modbus.protocol;

public import std.datetime : Duration, dur, hnsecs, usecs, nsecs, msecs, seconds;

import modbus.connection.tcp;
import std.socket : Socket, SocketSet, TcpSocket, SocketShutdown;

import modbus.connection.rtu;

public import serialport;
public import std.socket : InternetAddress;

/// Modbus master with RTU backend
class ModbusRTUMaster : ModbusMaster
{
protected:
    SerialPortConnection spcom;

public:

    ///
    this(SerialPort sp, SpecRules sr=null)
    {
        spcom = new SerialPortConnection(sp);
        super(new RTU(sr), spcom);
    }

    ///
    inout(SerialPort) port() inout @property { return spcom.port; }
}

/// Modbus slave with RTU backend
class ModbusRTUSlave : ModbusSlave
{
protected:
    SerialPortConnection spcom;

public:

    ///
    this(ModbusSlaveModel mdl, SerialPort sp, SpecRules sr=null)
    {
        spcom = new SerialPortConnection(sp);
        super(mdl, new RTU(sr), spcom);
    }

    ///
    inout(SerialPort) port() inout @property { return spcom.port; }
}

/// Modbus master with TCP backend based on TcpSocket from std.socket
class ModbusTCPMaster : ModbusMaster
{
protected:
    MasterTcpConnection mtc;

public:
    ///
    this(Address addr, void delegate(Duration) sf=null, SpecRules sr=null)
    {
        mtc = new MasterTcpConnection(addr, sf);
        super(new TCP(sr), mtc);
    }

    ///
    inout(Socket) socket() inout @property { return mtc.socket; }

    ///
    void halt() { mtc.close(); }
}

/// Modbus
class ModbusTCPSlaveServer
{
protected:

    import core.thread : Fiber;
    import modbus.msleep : msleep;

    ModbusSlaveModel model;
    TCP be;
    TcpSocket serv;
    SocketSet ss;

    void delegate(Duration) sleepFunc;

    void sleep(Duration d)
    {
        if (sleepFunc !is null) sleepFunc(d);
        else msleep(d);
    }

    void yield() { this.sleep(Duration.zero); }

    static class MBS : Fiber
    {
        ModbusSlave mb;
        SlaveTcpConnection con;

        this(ModbusSlave mb, SlaveTcpConnection con)
        {
            this.mb = mb;
            this.con = con;
            super(&run);
        }

        void run() { while (true) mb.iterate; }
    }

    MBS[] slaves;
    size_t maxConCount;

public:

    ///
    this(ModbusSlaveModel mdl, Address addr,
        void delegate(Duration) sf, SpecRules sr=null)
    { this(mdl, addr, 16, 128, sf, sr); }

    ///
    this(ModbusSlaveModel mdl, Address addr, int acceptConQueueLen=16,
         size_t maxConCount=128, void delegate(Duration) sf=null, SpecRules sr=null)
    {
        model = mdl;
        be = new TCP(sr);
        sleepFunc = sf;

        serv = new TcpSocket;
        serv.blocking = false;
        serv.bind(addr);
        serv.listen(acceptConQueueLen);
        this.maxConCount = maxConCount;

        ss = new SocketSet;
    }

    ///
    void iterate()
    {
        ss.reset();
        ss.add(serv);

        if (slaves.any!(a=>!a.con.isAlive))
        {
            debug version (unittest) auto oldCount = slaves.length;
            import std.range : enumerate;
            ptrdiff_t last=-1;
            foreach (i, s; enumerate(slaves.filter!(a=>a.con.isAlive)))
            {
                slaves[i] = s;
                last = i;
            }
            slaves.length = last+1;
            debug version (unittest) testPrintf!("reduce slaves: %d -> %d")(oldCount, slaves.length);
        }

        foreach (sl; slaves)
        {
            try sl.call;
            catch (CloseTcpConnection)
                sl.con.close();

            this.yield();
        }

        while (Socket.select(ss, null, null, Duration.zero) && ss.isSet(serv))
        {
            auto s = serv.accept;
            debug version (unittest) testPrintf!("slaves: %d [max %d]")(slaves.length, maxConCount);
            if (slaves.length >= maxConCount)
            {
                s.shutdown(SocketShutdown.BOTH);
                s.close();
                return;
            }
            auto con = new SlaveTcpConnection(s, sleepFunc);
            slaves ~= new MBS(new ModbusSlave(model, be, con), con);
            this.yield();
        }
    }

    ///
    inout(Socket) socket() inout @property { return serv; }

    ///
    void halt()
    {
        serv.shutdown(SocketShutdown.BOTH);
        serv.close();
    }
}

version (unittest):

import modbus.ut;

enum dataRegCnt = TestModbusSlaveDevice.Data.sizeof/2;

struct TInfo
{
    ulong mbn;
    string[2] dev;
    string mode;
    string addr;
    ushort port;
    Duration worktime;
}

struct Exc
{
    string msg;
    string file;
    size_t line;
}

Exc exc(string msg, string file=__FILE__, size_t line=__LINE__)
{ return Exc(msg, file, line); }

unittest
{
    mixin(mainTestMix);

    auto cp = getPlatformComPipe(BUFFER_SIZE);

    if (cp is null)
    {
        stderr.writeln(" platform doesn't support real test");
        return;
    }

    stderr.writefln(" port source `%s`\n", cp.command);
    try cp.open();
    catch (Exception e) stderr.writeln(" can't open com pipe: ", e.msg);
    scope (exit) cp.close();
    stderr.writefln(" pipe ports: %s <=> %s", cp.ports[0], cp.ports[1]);

    auto tInfo = TInfo(42, cp.ports, "8N1", "127.0.0.1", cast(ushort)uniform(8110, 8120), 5.seconds);

    ut!({
        size_t n;
        spawnLinked(&sFnc, tInfo); n++;
        spawnLinked(&mFnc, tInfo); n++;
        spawnLinked(&mTcpFnc, tInfo, true); n++;

        version (linux)
        {
            spawnLinked(&mTcpFnc, tInfo, false); n++;
        }

        foreach (i; 0 .. n)
            receive(
                (LinkTerminated lt) { },
                (Exc e) { throw new Exception(e.msg); }
                );
    }, "multiThread facade test");
}

void sFnc(TInfo info)
{
    try
    {
        auto mslp = delegate (Duration d) @nogc { msleep(d); };

        auto mdl = new MultiDevModbusSlaveModel;
        mdl.devs ~= new TestModbusSlaveDevice(info.mbn);

        auto sp = new SerialPortFR(info.dev[1], info.mode, mslp);
        scope (exit) sp.close();
        auto ia = new InternetAddress(info.addr, info.port);

        auto rtumbs = new ModbusRTUSlave(mdl, sp);
        auto tcpmbs = new ModbusTCPSlaveServer(mdl, ia, 16, 16, mslp);
        scope (exit) tcpmbs.halt();

        const sw = StopWatch(AutoStart.yes);
        while (sw.peek < info.worktime + 500.msecs)
        {
            rtumbs.iterate();
            tcpmbs.iterate();
            mslp(1.msecs);
        }
    }
    catch (Throwable e)
        send(ownerTid, exc(e.msg, e.file, e.line));
}

void mFnc(TInfo info)
{
    auto mslp = delegate (Duration d) @nogc { msleep(d); };

    auto sp = new SerialPortFR(info.dev[0], info.mode, mslp);
    scope (exit) sp.close();
    auto ia = new InternetAddress(info.addr, info.port);

    auto rtumbm = new ModbusRTUMaster(sp);
    auto tcpmbm = new ModbusTCPMaster(ia, mslp);
    rtumbm.connection.readTimeout = 1.seconds;
    tcpmbm.connection.readTimeout = 1.seconds;
    scope (exit) tcpmbm.halt();

    const sw = StopWatch(AutoStart.yes);
    try
    {
        while (sw.peek < info.worktime)
        {
            auto s = cast(ushort)uniform(0, dataRegCnt-2);
            auto c = cast(ushort)uniform(1, dataRegCnt-s);

            const(ushort)[] rtu_vals, tcp_vals;

            try rtu_vals = rtumbm.readInputRegisters(info.mbn, s, c);
            catch (Exception e) testPrint("RTU read throws: " ~ e.msg);

            try tcp_vals = tcpmbm.readInputRegisters(info.mbn, s, c);
            catch (Exception e) testPrint("TCP read throws: " ~ e.msg);

            if (rtu_vals != rtu_vals.init && tcp_vals != tcp_vals.init)
                if (!equal(rtu_vals, tcp_vals))
                    send(ownerTid, exc("fail check"));

            msleep(1.msecs);
        }
    }
    catch (Throwable e)
    {
        testPrint(__FUNCTION__~ " "~ e.msg);
        assert(0);
    }
}

void mTcpFnc(TInfo info, bool needHalt=false)
{
    auto mslp = delegate (Duration d) @nogc { msleep(d); };

    auto ia = new InternetAddress(info.addr, info.port);

    const sw = StopWatch(AutoStart.yes);
    while (sw.peek < info.worktime)
    {
        try
        {
            auto tcpmbm = new ModbusTCPMaster(ia, mslp);
            tcpmbm.connection.readTimeout = 1.seconds;
            auto vals = tcpmbm.readInputRegisters(info.mbn, 0, dataRegCnt);
            msleep(10.msecs);
            if (needHalt) tcpmbm.halt();
        }
        catch (Throwable e)
        {
            testPrintf!(__FUNCTION__~ " needHalt %s, msg: %s")(needHalt, e.msg);
            assert(0);
        }
        msleep(10.msecs);
    }
}