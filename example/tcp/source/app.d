import std.stdio;
import std.conv;

import modbus;

int main(string[] args)
{
    if (args.length < 5)
    {
        stderr.writeln("use: rid <IP> <PORT> <STARTREGISTER> <COUNT>");
        return 1;
    }
    auto addr = args[1];
    auto port = args[2].to!ushort;
    auto start = args[3].to!ushort;
    auto count = args[4].to!ushort;

    auto mbs = new ModbusTCP(new InternetAddress(addr, port));
    writeln(mbs.readInputRegisters(1, start, count));
    return 0;
}