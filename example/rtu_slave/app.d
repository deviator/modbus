import std.stdio;
import std.conv;
import std.datetime;
import core.thread;

import modbus;
import serialport;

class DevSim : ModbusSlave
{
    SerialPortConnection spc;
    ushort[] table;
    this(ulong dev, string port, uint baudrate)
    {
        auto sp = new SerialPort(port, baudrate);
        spc = new SerialPortConnection(sp);
        super(dev, spc, new RTU);

        table = [ 12,  23,  34,  45, 56,
                  67,  78,  89,  90, 123,
                 234, 345, 456, 567, 678];
    }

override:
    MsgProcRes onReadInputRegisters(ushort start, ushort count)
    {
        if (count == 0 || count > 125) return illegalDataValue;
        if (count >= table.length) return illegalDataValue;
        if (start >= table.length) return illegalDataAddress;

        return mpr(cast(ubyte)(count*2),
                   table[start..start+count]);
    }
}

void main(string[] args)
{
    auto port = args[1];
    auto baudrate = args[2].to!uint;
    auto dev = args[3].to!uint;
    auto ds = new DevSim(dev, port, baudrate);

    while (true)
    {
        ds.iterate();
        Thread.sleep(1.msecs);
    }
}