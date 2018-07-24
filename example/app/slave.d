import std.stdio;
import std.algorithm;
import std.conv;
import std.datetime.stopwatch;
import core.thread;

import modbus;

class DevSim : SimpleModbusSlaveDevice
{
    ushort[] buf;

    void upd()
    {
        buf = [ 12,  23,  34,  45, 56,
                67,  78,  89,  90, 123,
               234, 345, 456, 567, 678];
    }

    this(ulong dev)
    {
        super(dev);
        upd();
    }

    override Response onReadInputRegisters(ResponseWriter rw, ushort addr, ushort count)
    {
        if (count > 0x7D || count == 0)
            return Response.illegalDataValue;
        if (addr >= buf.length || addr+count > buf.length)
            return Response.illegalDataAddress;
        return rw.packArray(buf[addr..addr+count]);
    }
}

int main(string[] args)
{
    args.each!writeln;

    if (args.length < 4)
    {
        version (rtu) enum msg = "use: example_slave <COM> <BAUD> <DEV>";
        version (tcp) enum msg = "use: example_slave  <IP> <PORT> <DEV>";
        return fail(msg);
    }
    auto str = args[1];
    auto numb = args[2].to!uint;
    auto dev = args[3].to!uint;

    auto mdl = new MultiDevModbusSlaveModel;
    mdl.devices ~= new DevSim(dev);

    version (rtu)
    {
        pragma(msg, "RTU slave");
        auto ds = new ModbusRTUSlave(mdl, new SerialPortBlk(str, numb));
    }
    else version (tcp)
    {
        pragma(msg, "TCP slave");
        auto ds = new ModbusTCPSlaveServer(mdl, new InternetAddress(str, cast(ushort)numb));
    }
    else static assert(0, "unknown version");

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