/// modbus with back end
module modbus.facade;

import modbus.backend;
import modbus.protocol;

public import std.datetime : Duration, dur, hnsecs, nsecs, msecs, seconds;

import modbus.connection.tcp;
import std.socket : TcpSocket;

import modbus.connection.rtu;

/// ModbusMaster with RTU backend
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

/// ModbusSingleSlave with RTU backend
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

/// Modbus with TCP backend based on TcpSocket from std.socket
class ModbusTCPMaster : ModbusMaster
{
protected:
    MasterTcpConnection mtc;

public:
    ///
    this(Address addr, SpecRules sr=null)
    {
        mtc = new MasterTcpConnection(addr);
        super(new TCP(sr), mtc);
    }

    ///
    inout(TcpSocket) socket() inout @property { return mtc.socket; }

    ~this() { mtc.socket.close(); }
}

///
class ModbusTCPSlave : ModbusSlave
{
protected:
    SlaveTcpConnection mtc;

public:
    ///
    this(ModbusSlaveModel mdl, Address addr, SpecRules sr=null)
    {
        mtc = new SlaveTcpConnection(addr);
        super(mdl, new TCP(sr), mtc);
    }

    ///
    inout(TcpSocket) socket() inout @property { return mtc.socket; }

    ~this() { mtc.socket.close(); }
}

version (unittest): package:

enum BUFFER_SIZE = 1024;

interface ComPipe
{
    void open();
    void close();
    string command() const @property;
    string[2] ports() const @property;
}

class SocatPipe : ComPipe
{
    int bufferSize;
    ProcessPipes pipe;
    string[2] _ports;
    string _command;

    this(int bs)
    {
        bufferSize = bs;
        _command = ("socat -d -d -b%d pty,raw,"~
                    "echo=0 pty,raw,echo=0").format(bufferSize);
    }

    static string parsePort(string ln)
    {
        auto ret = ln.split[$-1];
        enforce(ret.startsWith("/dev/"),
        "unexpected last word in output line '%s'".format(ln));
        return ret;
    }

    override void close()
    {
        if (pipe.pid is null) return;
        kill(pipe.pid);
    }

    override void open()
    {
        pipe = pipeShell(_command);
        _ports[0] = parsePort(pipe.stderr.readln.strip);
        _ports[1] = parsePort(pipe.stderr.readln.strip);
    }
    
    override const @property
    {
        string command() { return _command; }
        string[2] ports() { return _ports; }
    }
}

unittest
{
    enum socat_out_ln = "2018/03/08 02:56:58 socat[30331] N PTY is /dev/pts/1";
    assert(SocatPipe.parsePort(socat_out_ln) == "/dev/pts/1");
    assertThrown(SocatPipe.parsePort("some string"));
}

class DefinedPorts : ComPipe
{
    string[2] env;
    string[2] _ports;

    this(string[2] envNames = ["MODBUS_TEST_COMPORT1", "MODBUS_TEST_COMPORT2"])
    { env = envNames; }

override:

    void open()
    {
        import std.process : environment;
        import std.range : lockstep;
        import std.algorithm : canFind;

        auto lst = SerialPort.listAvailable;

        foreach (ref e, ref p; lockstep(env[], _ports[]))
        {
            p = environment[e];
            enforce(lst.canFind(p), new Exception("unknown port '%s' in env var '%s'".format(p, e)));
        }
    }

    void close() { }

    string command() const @property
    {
        return "env: %s=%s, %s=%s".format(
            env[0], _ports[0],
            env[1], _ports[1]
        );
    }

    string[2] ports() const @property { return _ports; }
}

ComPipe getPlatformComPipe(int bufsz)
{
    try
    {
        auto ret = new DefinedPorts;
        ret.open();
        return ret;
    }
    catch (Exception e)
    {
        stderr.writeln();
        stderr.writeln(" error while open predefined ports: ", e.msg);
        version (Posix) return new SocatPipe(bufsz);
        else return null;
    }
}

import modbus.ut;

unittest
{
    mixin(mainTestMix);

    auto cp = getPlatformComPipe(BUFFER_SIZE);
    scope (exit) cp.close();

    if (cp is null)
    {
        stderr.writeln(" platform doesn't support real test");
        return;
    }

    stderr.writefln(" port source `%s`\n", cp.command);
    cp.open();
    stderr.writefln(" pipe ports: %s <=> %s", cp.ports[0], cp.ports[1]);

    ut!fiberBasedRTU(cp.ports);
    ut!fiberBasedTCP(new InternetAddress("127.0.0.1", 8100));
}

void fiberBasedRTU(string[2] ports)
{
    enum spmode = "8N1";

    import std.typecons : scoped;

    auto p1 = scoped!SerialPortFR(ports[0], spmode);
    auto p2 = scoped!SerialPortFR(ports[1], spmode);
    p1.flush();
    p2.flush();

    alias SPC = SerialPortConnection;

    testPrint("try RTU BE");
    baseModbusTest!RTU(new SPC(p1), new SPC(p2));
    testPrint("try TCP BE");
    baseModbusTest!TCP(new SPC(p1), new SPC(p2));
}

void fiberBasedTCP(Address addr)
{
    auto sc = new SlaveTcpConnection(addr);
    scope (exit) sc.socket.close();
    auto mc = new MasterTcpConnection(addr);
    scope (exit) mc.socket.close();
    testPrint("try TCP BE");
    baseModbusTest!TCP(mc, sc);
    testPrint("try RTU BE");
    baseModbusTest!RTU(mc, sc);
}