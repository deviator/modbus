import std.stdio;
import std.algorithm;
import std.conv;
import std.datetime.stopwatch;
import core.thread;

import modbus;

import aslike;

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

interface Iterable { void iterate(); }

int main(string[] args)
{
    args.each!writeln;

    if (args.length < 5) return usage(1);

    const cmd = args[1];
    auto str = args[2];
    auto numb = args[3].to!uint;
    auto dev = args[4].to!uint;

    auto mdl = new MultiDevModbusSlaveModel;
    mdl.devices ~= new DevSim(dev);

    Like!Iterable ds;

    if (cmd == "RTU")
        ds = (new ModbusRTUSlave(mdl, new SerialPortBlk(str, numb))).as!Iterable;
    else if (cmd == "TCP")
        ds = (new ModbusTCPSlaveServer(mdl, new InternetAddress(str, cast(ushort)numb))).as!Iterable;
    else return usage(1);

    writefln("start");
    stdout.flush();
    while (true)
    {
        ds.iterate();
        Thread.sleep(1.msecs);
    }
}

int usage(int code)
{
    stderr.writeln("use: example_slave RTU <COM> <BAUD> <DEV>");
    stderr.writeln(" or: example_slave TCP  <IP> <PORT> <DEV>");
    return code;
}

int fail(string str)
{
    stderr.writeln(str);
    return 1;
}