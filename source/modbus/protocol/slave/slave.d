///
module modbus.protocol.slave.slave;

import modbus.protocol.base;
public import modbus.types;

import modbus.protocol.slave.model;
import modbus.protocol.slave.types;

/++ Base class for modbus slave devices

    Iteration and message parsing process

    Define types
 +/
class ModbusSlave : Modbus
{
protected:
    size_t readed;

    void[MAX_BUFFER] responseBuffer;

    class MBSRW : ResponseWriter
    {
        override @property
        {
            Backend backend() { return this.outer.be; }
            protected void[] buffer() { return responseBuffer; }
        }
    }

    MBSRW rw;

    StopWatch dt;

    ModbusSlaveModel model;

    ///
    alias Reaction = ModbusSlaveModel.Reaction;

    /// process message and send result if needed
    void processMessage(ref const Message msg)
    {
        import std.experimental.logger : errorf;

        Response res;
        try
        {
            auto pm = model.checkDeviceNumber(msg.dev);
            if (pm == Reaction.none) return;
            res = model.onMessage(rw, msg);
            if (pm == Reaction.processAndAnswer)
                this.write(msg.dev, msg.fnc | (res.error ? 0x80 : 0), res.data);
        }
        catch (SlaveFuncProcessException e)
        {
            errorf("%s", e);
            this.write(msg.dev, msg.fnc | 0x80, e.code);
        }
        catch (Throwable e)
        {
            errorf("%s", e);
            this.write(msg.dev, msg.fnc | 0x80,
                    FunctionErrorCode.slaveDeviceFailure);
        }
    }

public:
    ///
    this(ModbusSlaveModel mdl, Backend be, Connection con)
    {
        super(be, con);
        this.model = mdl;
        con.readTimeout = 0.msecs;

        rw = new MBSRW;
    }

    ///
    void iterate()
    {
        Message msg;

        void reset()
        {
            dt.stop();
            dt.reset();
            readed = 0;
        }

        if (dt.peek > con.readTimeout * MAX_BUFFER)
        {
            version (modbus_verbose)
            {
                .trace("so long read, reset");
            }
            reset();
        }

        size_t nr;

        do
        {
            nr = con.read(buffer[readed..readed+1], con.CanRead.zero).length;
            readed += nr;

            version (modbus_verbose) if (nr)
            {
                .trace(" now readed: ", nr);
                .trace("full readed: ", readed);
                .trace("     readed: ", cast(ubyte[])buffer[0..readed]);
            }
        }
        while (nr && readed < buffer.length);

        if (!readed) return;
        if (!dt.running) dt.start();

        bool parsed;
        size_t started;
        do 
        {
            parsed = be.parseMessage(buffer[started..readed], msg) == be.ParseResult.success;
            started++;
        }
        while (!parsed && started < readed);

        if (parsed) processMessage(msg);
        if (parsed || buffer.length == readed) reset();
    }
}