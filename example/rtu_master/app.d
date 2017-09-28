import std.stdio;
import std.conv;

import modbus;

void main(string[] args)
{
    if (args.length < 6)
    {
        stderr.writeln("args error");
        return;
    }

    auto mm = new ModbusRTUMaster(args[1], args[2].to!uint);

    auto dev = args[3].to!uint;
    auto start = args[4].to!ushort;
    auto count = args[5].to!ushort;

    auto data = mm.readInputRegisters(dev, start, count);

    writefln("dev #%d\naddr: %d\ncount: %d\ndata: %s", dev, start, count, data);
}