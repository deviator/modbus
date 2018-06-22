///
module modbus.protocol.slave.slave;

import modbus.protocol.base;
public import modbus.types;

import modbus.protocol.slave.model;
import modbus.protocol.slave.types;

import modbus.cbuffer;

/++ Base class for modbus slave devices

    Iteration and message parsing process

    Define types
 +/
class ModbusSlave : Modbus
{
protected:
    size_t readed;

    void[MAX_BUFFER] responseBuffer;
    void[MAX_BUFFER*2] findMsgBuf;

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

    CBuffer cbuffer;

    enum MIN_MSG = 4;

    MessageFinder messageFinder;

public:

    ///
    static class MessageFinder
    {
        Backend backend;

        final bool testMessage(const(void)[] data, ref Message msg)
        { return backend.parseMessage(data, msg) == backend.ParseResult.success; }

        ///
        abstract ptrdiff_t[2] findMessage(const(void)[] data, ref Message msg);
    }

    ///
    static class SlaveMessageFinder : MessageFinder
    {
        override ptrdiff_t[2] findMessage(const(void)[] data, ref Message msg)
        {
            assert(backend !is null);
            if (data.length >= MIN_MSG)
                foreach (s; 0 .. data.length - MIN_MSG + 1)
                    if (testMessage(data[s..$], msg))
                        return [s, data.length];
            return [-1, -1];
        }
    }

    ///
    static class SnifferMessageFinder : MessageFinder
    {
        override ptrdiff_t[2] findMessage(const(void)[] data, ref Message msg)
        {
            if (data.length >= MIN_MSG)
                foreach (s; 0 .. data.length - MIN_MSG + 1)
                    foreach_reverse (n; s + MIN_MSG .. data.length + 1)
                        if (testMessage(data[s..n], msg))
                            return [s, n+1];
            return [-1, -1];
        }
    }

    ///
    this(ModbusSlaveModel mdl, Backend be, Connection con, MessageFinder mf=null)
    {
        super(be, con);
        this.model = mdl;
        con.readTimeout = 10.msecs;

        messageFinder = mf is null ? new SlaveMessageFinder : mf;
        messageFinder.backend = be;

        rw = new MBSRW;
        cbuffer = CBuffer(MAX_BUFFER*2);
    }

    ///
    void iterate()
    {
        auto rdd = con.read(buffer[], con.CanRead.zero);
        auto df = cbuffer.capacity - cbuffer.length - rdd.length;
        if (df < 0) cbuffer.popFrontN(-df);
        cbuffer.put(rdd);
        auto data = cbuffer.fill(findMsgBuf);

        Message msg;
        auto se = messageFinder.findMessage(data, msg);
        if (se[0] == -1) return;
        processMessage(msg);
        cbuffer.popFrontN(se[1]);
    }
}