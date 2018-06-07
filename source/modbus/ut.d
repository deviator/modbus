module modbus.ut;

version (unittest): package:

public
{
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
}

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
    catch (Throwable e)
    {
        stderr.writeln();
        stderr.writeln(" error while open predefined ports: ", e.msg);
        version (Posix) return new SocatPipe(bufsz);
        else return null;
    }
}