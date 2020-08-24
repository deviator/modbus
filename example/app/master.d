import std : to, map, array, stderr, stdout, writeln, msecs, toLower;

import modbus;

int usage(int code)
{
    stderr.writeln("use: example_master RTU     <COM> <BAUD> <DEV> <FN> <ADDR> <PARAMS>");
    stderr.writeln(" or: example_master TCP[4|6] <IP> <PORT> <DEV> <FN> <ADDR> <PARAMS>");
    return code;
}

int main(string[] args)
{
    args.each!writeln;

    if (args.length < 7) return usage(1);

    ModbusMaster mm;

    const cmd = args[1];
    if (cmd == "RTU")
    {
        auto sp = new SerialPortBlk(args[2], args[3].to!uint);
        auto mtmp = new ModbusRTUMaster(sp);
        mtmp.port.flush(); // in case if before start serial port has data
        mm = mtmp;
    }
    else if (cmd.startsWith("TCP"))
    {
        //import modbus.connection.tcp;
        import std.socket;
        Address ia;
        if (cmd == "TCP" || cmd.endsWith("4"))
            ia = new InternetAddress(args[2], args[3].to!ushort);
        else if (cmd.endsWith("6"))
            ia = new Internet6Address(args[2], args[3].to!ushort);
        else
        {
            stderr.writeln("unknown cmd: " ~ cmd);
            return usage(1);
        }
        auto mtmp = new ModbusTCPMaster(ia);
        mtmp.connection.readTimeout = 1000.msecs;
        mm = mtmp;
    }
    else
    {
        stderr.writeln("unknown cmd: " ~ cmd);
        return usage(1);
    }

    const dev = args[4].to!uint;
    const fn = args[5].to!ushort;
    const addr = args[6].to!ushort;
    const params = args[7..$].map!(a=>a.to!ushort).array;

    stdout.writefln("start");
    stdout.flush();
    switch (fn)
    {
        case 1:
            const data = mm.readCoils(dev, addr, params[0]);
            stdout.writefln("dev #%d\naddr: %d\ncount: %d\ndata: %s", dev, addr, params[0], data);
            break;
        case 2:
            const data = mm.readDiscreteInputs(dev, addr, params[0]);
            stdout.writefln("dev #%d\naddr: %d\ncount: %d\ndata: %s", dev, addr, params[0], data);
            break;
        case 3:
            const data = mm.readHoldingRegisters(dev, addr, params[0]);
            stdout.writefln("dev #%d\naddr: %d\ncount: %d\ndata: %s", dev, addr, params[0], data);
            break;
        case 4:
            const data = mm.readInputRegisters(dev, addr, params[0]);
            stdout.writefln("dev #%d\naddr: %d\ncount: %d\ndata: %s", dev, addr, params[0], data);
            break;
        case 5:
            mm.writeSingleCoil(dev, addr, !!params[0]);
            break;
        case 6:
            mm.writeSingleRegister(dev, addr, params[0]);
            break;
        case 15:
            mm.writeMultipleCoils(dev, addr, params[0], params[1..$]);
            break;
        case 16:
            mm.writeMultipleRegisters(dev, addr, params);
            break;
        default:
            stderr.writeln("unsupported function");
            break;
    }
    return 0;
}
