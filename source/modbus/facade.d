/// modbus with back end
module modbus.facade;

import modbus.backend;
import modbus.protocol;

public import std.datetime : Duration, dur, hnsecs, usecs, nsecs, msecs, seconds;

import modbus.connection.tcp;
import std.socket : Socket, SocketSet, TcpSocket, SocketShutdown;

import modbus.connection.rtu;

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

    ~this()
    {
        mtc.socket.shutdown(SocketShutdown.BOTH);
        mtc.socket.close();
    }
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

        while (Socket.select(ss, null, null, Duration.zero))
        {
            auto s = serv.accept;
            if (slaves.length >= maxConCount)
            {
                s.shutdown(SocketShutdown.BOTH);
                s.close();
                continue;
            }
            auto con = new SlaveTcpConnection(s, sleepFunc);
            slaves ~= new MBS(new ModbusSlave(model, be, con), con);
            this.sleep(Duration.zero);
        }

        if (slaves.any!(a=>!a.con.isAlive))
            slaves = slaves.filter!(a=>a.con.isAlive).array;

        foreach (sl; slaves)
        {
            try sl.call;
            catch (CloseTcpConnection)
                sl.con.close();

            this.sleep(Duration.zero);
        }
    }

    ///
    inout(Socket) socket() inout @property { return serv; }

    ~this()
    {
        serv.shutdown(SocketShutdown.BOTH);
        serv.close();
    }
}