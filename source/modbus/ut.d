module modbus.ut;

version (unittest): package:

import core.thread;

import std.array;
import std.algorithm;
import std.concurrency;
import std.conv;
import std.datetime.stopwatch;
import std.exception;
import std.format;
import std.random;
import std.range;
import std.stdio : stderr;
import std.string;
import std.random;
import std.process;

import modbus.connection;
import modbus.backend;
import modbus.protocol.master;
import modbus.msleep;

enum test_print_offset = "    ";

void testPrint(string s) { stderr.writeln(test_print_offset, s); }
void testPrintf(string fmt="%s", Args...)(Args args)
{ stderr.writefln!(test_print_offset~fmt)(args); }

void ut(alias fnc, string uname="", Args...)(Args args)
{
    static if (uname.length)
        enum name = uname;
    else
        enum name = __traits(identifier, fnc);
    stderr.writefln!" >> run %s"(name);
    fnc(args);
    scope (success) stderr.writefln!" << success %s\n"(name);
    scope (failure) stderr.writefln!" !! failure %s\n"(name);
}

enum mainTestMix = `
    stderr.writefln!"=== start %s test {{{\n"(__MODULE__);
    scope (success) stderr.writefln!"}}} finish %s test ===\n"(__MODULE__);
    scope (failure) stderr.writefln!"}}} fail %s test  !!!"(__MODULE__);
    `;

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
    string[2] _ports = ["./tmp1.port", "./tmp2.port"];
    string _command;

    this(int bs)
    {
        bufferSize = bs;
        _command = format!"socat -b%d pty,raw,echo=0,link=%s pty,raw,echo=0,link=%s"
                    (bufferSize, _ports[0], _ports[1]);
    }

    override void close()
    {
        if (pipe.pid is null) return;
        kill(pipe.pid);
    }

    override void open()
    {
        pipe = pipeShell(_command);
        Thread.sleep(1000.msecs); // wait for socat create ports
    }
    
    override const @property
    {
        string command() { return _command; }
        string[2] ports() { return _ports; }
    }
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
    catch (Throwable e)
    {
        stderr.writeln();
        stderr.writeln(" error while open predefined ports: ", e.msg);
        version (Posix) return new SocatPipe(bufsz);
        else return null;
    }
}

// slave tests

import modbus;

unittest
{
    mixin(mainTestMix);

    ut!fiberVirtualPipeBasedTest();

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

    ut!fiberSerialportBasedTest(cp.ports);
}

void fiberVirtualPipeBasedTest()
{
    auto con = virtualPipeConnection(256, "test");
    baseModbusTest!RTU(con[0], con[1]);
    baseModbusTest!TCP(con[0], con[1]);
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

    baseModbusTest!RTU(new SPC(p1), new SPC(p2));
    baseModbusTest!TCP(new SPC(p1), new SPC(p2));
}

void baseModbusTest(Be: Backend)(Connection masterCon, Connection slaveCon, Duration rtm=500.msecs)
{
    enum DN = 13;
    testPrintf!"BE: %s"(Be.classinfo.name);

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
        master.writeSingleRegister(DN, 15, 0xABCD);
        assert((*originData).usv[1] == 0xABCD);

        finish = true;
    }

    void sfnc()
    {
        auto device = new TestModbusSlaveDevice(DN);
        originData = &device.data;

        auto model = new MultiDevModbusSlaveModel;
        model.devices ~= device;

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