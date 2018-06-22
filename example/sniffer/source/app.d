import std.stdio;
import std.getopt;

import serialport;
import modbus;

class Sniffer : ModbusSlaveModel
{
    bool hideMaster, hideSlave, hideUnknown;

    this(bool hm, bool hs)
    {
        hideMaster = hm;
        hideSlave = hs;
    }

    enum Source
    {
        unknown,
        master,
        slave
    }

    static string sourceStr(Source s)
    {
        final switch(s) with (Source)
        {
            case unknown: return "U";
            case master: return "M";
            case slave: return "S";
        }
    }

    Source expSrc = Source.unknown;

    void swapSource()
    {
        with (Source)
        {
            if (expSrc == unknown) return;
            else if (expSrc == master) expSrc = slave;
            else expSrc = master;
        }
    }

    Source detectSource(ref const Message msg)
    {
        if (msg.fnc > 0x80) return Source.slave;

        switch (msg.fnc) with (FunctionCode)
        {
            case readCoils:
            case readDiscreteInputs:
            case readHoldingRegisters:
            case readInputRegisters:
                return msg.data.length % 2 ? Source.slave : Source.master;

            case writeSingleCoil:
            case writeSingleRegister:
                return Source.unknown;

            case writeMultipleCoils:
            case writeMultipleRegisters:
                return msg.data.length % 2 ? Source.master : Source.slave;

            default: return Source.unknown;
        }
    }

    void process(ref const Message msg)
    {
        auto tmp = detectSource(msg);
        if (tmp != Source.unknown)
        {
            if (expSrc != Source.unknown)
            {
                if (expSrc != tmp)
                {
                    stderr.writeln("warn: unexpected source ", tmp);
                    expSrc = tmp;
                }
            }
            else
            {
                stderr.writeln("detect source ", tmp);
                expSrc = tmp;
            }
        }

        if ((expSrc == Source.master && !hideMaster) ||
            (expSrc == Source.slave && !hideSlave) ||
            (expSrc == Source.unknown && !hideUnknown))
        {
            writefln!("[%s] #%03d F: 0x%02x (%02d) %s"~
                    "\n    hex[%(%02x %)]\n    dec[%(%03d %)]")(
                        sourceStr(expSrc), msg.dev,
                        msg.fnc, msg.fnc,
                        cast(FunctionCode)msg.fnc,
                        cast(const(ubyte)[])msg.data,
                        cast(const(ubyte)[])msg.data,
                    );
            stdout.flush();
        }

        swapSource();
    }
    
override:
    Reaction checkDeviceNumber(ulong dev)
    { return Reaction.onlyProcessMessage; }

    Response onMessage(ResponseWriter rw, ref const Message msg)
    {
        process(msg);
        return Response.illegalFunction;
    }
}

void main(string[] args)
{
    string port = "/dev/ttyUSB0";
    int baud = 9600;
    bool hideMaster = false;
    bool hideSlave = true;

    getopt(args,
            "p|port", &port,
            "b|baud", &baud,
            "hide-master", &hideMaster,
            "hide-slave", &hideSlave
            );

    auto sp = new SerialPortBlk(port, baud, "8N1");
    sp.flush();

    auto mdl = new Sniffer(hideMaster, hideSlave);
    auto mb = new ModbusRTUSlave(mdl, sp, null, new ModbusSlave.SnifferMessageFinder);

    while (true) mb.iterate();
}