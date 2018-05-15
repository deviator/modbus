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
class ModbusSlaveBase : Modbus
{
protected:
    size_t readed;

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
            res = model.onMessage(msg, be);
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
    this(Backend be, Connection con, ModbusSlaveModel model)
    {
        super(be, con);
        this.model = model;
    }

    ///
    alias Function = Response delegate(Message);

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

        if (dt.peek > con.readTimeout * 5) reset();

        size_t nr;

        do
        {
            try nr = con.read(buffer[readed..readed+1]).length;
            catch (TimeoutException e) nr = 0;
            readed += nr;

            version (modbus_verbose) if (nr)
            {
                import std.stdio;
                stderr.writeln(" now readed: ", nr);
                stderr.writeln("full readed: ", readed);
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