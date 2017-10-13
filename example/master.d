import std.algorithm;
import std.stdio;
import std.conv;

import modbus;

int main(string[] args)
{
    args.each!writeln;
    version (rtu)
    {
        pragma(msg, "RTU master");
        if (args.length < 6)
        {
            stderr.writeln("use: example_master <COM> <BAUDRATE> <DEV> <START> <COUNT>");
            return 1;
        }

        auto mm = new ModbusRTUMaster(args[1], args[2].to!uint);
    }
    else version (tcp)
    {
        pragma(msg, "TCP master");
        if (args.length < 6)
        {
            stderr.writeln("use: example_master <IP> <PORT> <DEV> <START> <COUNT>");
            return 1;
        }

        import modbus.connection.tcp;
        auto mm = new ModbusMaster(
                    new MasterTcpConnection(
                        new InternetAddress(args[1], args[2].to!ushort)));
    }
    else static assert(0, "unknown version");

    auto dev = args[3].to!uint;
    auto start = args[4].to!ushort;
    auto count = args[5].to!ushort;

    writefln("start");
    stdout.flush();
    auto data = mm.readInputRegisters(dev, start, count);
    writefln("dev #%d\naddr: %d\ncount: %d\ndata: %s", dev, start, count, data);
    return 0;
}