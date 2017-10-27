import std.stdio;
import std.algorithm;
import std.conv;
import std.datetime;
import core.thread;

import modbus;
import serialport;

class DevSim : ModbusSlave
{
    ushort[] table;

    void upd()
    {
        table = [ 12,  23,  34,  45, 56,
                  67,  78,  89,  90, 123,
                 234, 345, 456, 567, 678];
    }

    this(ulong dev, Backend be)
    {
        super(dev, be);
        upd();
        func[FuncCode.readInputRegisters] = (m)
        {
            auto start = be.unpackT!ushort(m.data[0..2]);
            auto count = be.unpackT!ushort(m.data[2..4]);

            if (count == 0 || count > 125) return illegalDataValue;
            if (count >= table.length) return illegalDataValue;
            if (start >= table.length) return illegalDataAddress;

            return packResult(cast(ubyte)(count*2),
                    table[start..start+count]);
        };
    }
}

int main(string[] args)
{
    args.each!writeln;
    version (rtu)
    {
        pragma(msg, "RTU slave");
        if (args.length < 4) return fail("use: example_slave <COM> <BAUDRATE> <DEV>");
        auto be = new RTU(new SerialPortConnection(new SerialPort(args[1], args[2].to!uint)));
    }
    else version (tcp)
    {
        pragma(msg, "TCP slave");
        if (args.length < 4) return fail("use: example_slave <IP> <PORT> <DEV>");
        auto be = new TCP(new SlaveTcpConnection(new InternetAddress(args[1], args[2].to!ushort)));
    }
    else static assert(0, "unknown version");

    auto dev = args[3].to!uint;
    auto ds = new DevSim(dev, be);

    writefln("start");
    stdout.flush();
    while (true)
    {
        ds.iterate();
        Thread.sleep(1.msecs);
    }
}

int fail(string str)
{
    stderr.writeln(str);
    return 1;
}