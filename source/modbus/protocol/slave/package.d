///
module modbus.protocol.slave;

public import modbus.protocol.slave.slave;
public import modbus.protocol.slave.model;
public import modbus.protocol.slave.device;

version (unittest) package(modbus):

import modbus.ut;

import modbus.connection;
import modbus.backend;
import modbus.protocol.master;

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

        import serialport;
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

unittest
{
    mixin(mainTestMix);
    auto cp = getPlatformComPipe(BUFFER_SIZE);
    scope (exit) cp.close();

    auto con = virtualPipeConnection(256, "test");
    ut!(baseModbusTest!RTU)(con[0], con[1]);
    ut!(baseModbusTest!TCP)(con[0], con[1]);

    if (cp is null)
    {
        stderr.writeln(" platform doesn't support real test");
        return;
    }

    stderr.writefln(" port source `%s`\n", cp.command);
    cp.open();
    stderr.writefln(" pipe ports: %s <=> %s", cp.ports[0], cp.ports[1]);

    ut!fiberSerialportBasedTest(cp.ports);
}

void fiberSerialportBasedTest(string[2] ports)
{
    enum spmode = "8N1";

    import std.typecons : scoped;
    import serialport;
    import modbus.connection.rtu;

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

void baseModbusTest(Be: Backend)(Connection masterCon, Connection slaveCon, Duration rtm=500.msecs)
{
    enum DN = 13;

    enum dln = TestModbusSlaveDevice.Data.sizeof / 2;
    ushort[] origin = void;
    TestModbusSlaveDevice.Data* originData;

    bool finish;

    void mfnc()
    {
        auto master = new ModbusMaster(new Be, masterCon);
        masterCon.readTimeout = rtm;
        Fiber.getThis.yield();
        auto dt = master.readInputRegisters(DN, 0, dln);
        assert( equal(origin, dt) );
        assert( equal(origin[2..4], master.readHoldingRegisters(DN, 2, 2)) );

        master.writeMultipleRegisters(DN, 2, [0xBEAF, 0xDEAD]);
        assert((*originData).value2 == 0xDEADBEAF);
        stderr.writeln(*originData);
        master.writeSingleRegister(DN, 15, 0xABCD);
        stderr.writeln(*originData);
        assert((*originData).usv[1] == 0xABCD);

        finish = true;
    }

    void sfnc()
    {
        auto device = new TestModbusSlaveDevice(DN);
        originData = &device.data;

        auto model = new MultiDevModbusSlaveModel;
        model.devs ~= device;

        auto slave = new ModbusSlave(model, new Be, slaveCon);
        Fiber.getThis.yield();
        while (!finish)
        {
            origin = cast(ushort[])((cast(void*)&device.data)[0..dln*2]);
            slave.iterate();
            Fiber.getThis.yield();
        }
    }

    auto mfiber = new Fiber(&mfnc);
    auto sfiber = new Fiber(&sfnc);

    bool work = true;
    int step;
    while (work)
    {
        alias TERM = Fiber.State.TERM;
        if (mfiber.state != TERM) mfiber.call;
        //stderr.writeln(getBuffer());
        if (sfiber.state != TERM) sfiber.call;

        step++;
        //stderr.writeln(getBuffer());
        Thread.sleep(10.msecs);
        if (mfiber.state == TERM && sfiber.state == TERM)
            work = false;
    }
}