///
module modbus.protocol.slave;

import modbus.protocol.base;
public import modbus.types;

/++ Base class for modbus slave devices

    Iteration and message parsing process

    Define types

    need override `checkDeviceNumber` and `onMessage`
 +/
class ModbusSlaveBase : Modbus
{
protected:
    size_t readed;

    StopWatch dt;

    /+ need separate with Modbus.buffer because
       otherwise in Modbus.write Modbus.buffer
       start pack with device number and function
       and can override answer data
     +/
    void[MAX_BUFFER] mBuffer;

    ///
    enum Reaction
    {
        none, ///
        onlyProcessMessage, ///
        processAndAnswer ///
    }

    ///
    abstract Reaction checkDeviceNumber(ulong dev);

    /++
        Example:
        ---
        if (msg.fnc == FuncCode.readInputRegisters)
            return packResult(/* return data */);
        return illegalFunction;
        ---
     +/
    abstract MsgProcRes onMessage(ref const Message msg);

    static MsgProcRes failMsgProcRes(T)(T val)
    { return MsgProcRes(cast(void[])[val], 1); }

    /// process message and send result if needed
    void processMessage(ref const Message msg)
    {
        MsgProcRes res;
        try
        {
            auto pm = checkDeviceNumber(msg.dev);
            if (pm == Reaction.none) return;
            res = onMessage(msg);
            if (pm == Reaction.processAndAnswer)
                this.write(msg.dev, msg.fnc | (res.error ? 0x80 : 0), res.data);
        }
        catch (Throwable e)
        {
            import std.experimental.logger;
            errorf("%s", e);
            this.write(msg.dev, msg.fnc | 0x80,
                    FunctionErrorCode.SLAVE_DEVICE_FAILURE);
        }
    }

public:
    ///
    this(Backend be, void delegate(Duration) sf=null)
    {
        super(be, sf);
        // approx 10 bytes (10 bits) on 9600 speed
        readTimeout = (cast(ulong)(1e7/96.0)).hnsecs;
    }

    ///
    struct MsgProcRes
    {
        ///
        void[] data;
        ///
        uint error;
    }

    ///
    enum illegalFunction = failMsgProcRes(FunctionErrorCode.ILLEGAL_FUNCTION);
    ///
    enum illegalDataValue = failMsgProcRes(FunctionErrorCode.ILLEGAL_DATA_VALUE);
    ///
    enum illegalDataAddress = failMsgProcRes(FunctionErrorCode.ILLEGAL_DATA_ADDRESS);
    ///
    enum slaveDeviceFailure = failMsgProcRes(FunctionErrorCode.SLAVE_DEVICE_FAILURE);

    ///
    alias Function = MsgProcRes delegate(Message);

    /// Functions
    enum FuncCode : ubyte
    {
        readCoils             = 0x1,  /// 0x1 (1)
        readDiscreteInputs    = 0x2,  /// 0x2 (2)
        readHoldingRegisters  = 0x3,  /// 0x3 (3)
        readInputRegisters    = 0x4,  /// 0x4 (4)
        writeSingleCoil       = 0x5,  /// 0x5 (5)
        writeSingleRegister   = 0x6,  /// 0x6 (6)
        writeMultipleRegister = 0x10, /// 0x10 (16)
    }

    ///
    MsgProcRes packResult(Args...)(Args args)
    {
        static void appendData(T)(void[] buf, T data, Backend backend, ref size_t start)
        {
            import std.traits : isArray;
            import std.range : isInputRange;
            static if (isArray!T || isInputRange!T)
            {
                foreach (e; data)
                    appendData(buf, e, backend, start);
            }
            else
            {
                auto p = backend.packT(data);
                auto end = start + p.length;
                if (end > buf.length)
                    throw modbusException("fill message buffer: to many args for pack data");
                buf[start..end] = p;
                start = end;
            }
        }

        size_t filled;

        foreach (arg; args)
            appendData(mBuffer[], arg, be, filled);

        return MsgProcRes(mBuffer[0..filled]);
    }

    ///
    void iterate()
    {
        Message msg;

        if (dt.peek.to!Duration > readTimeout)
        {
            dt.stop();
            readed = 0;
        }

        size_t now_readed;

        do
        {
            now_readed = be.connection.read(buffer[readed..$]).length;
            readed += now_readed;
            version (modbus_verbose) if (now_readed)
            {
                import std.stdio;
                stderr.writeln(" now readed: ", now_readed);
                stderr.writeln("full readed: ", readed);
            }
        }
        while (now_readed);

        if (!readed) return;
        if (!dt.running) dt.start();

        auto res = be.parseMessage(buffer[0..readed], msg);

        with (Backend.ParseResult) final switch(res)
        {
            case success:
                processMessage(msg);
                readed = 0;
                break;
            case errorMsg: /+ master send error? WTF? +/ break;
            case uncomplete: break;
            case checkFail: break;
        }
    }

    /// aux function
    ushort[2] parseMessageFirstTwoUshorts(ref const Message m)
    {
        return [be.unpackT!ushort(m.data[0..2]),
                be.unpackT!ushort(m.data[2..4])];
    }
}

/++ One device modbus slave

    Usage:
        set device, backend and sleep function (optional) in ctor
        add process funcs (use modbus methods for parsing packs)
        profit
 +/
class ModbusSingleSlave : ModbusSlaveBase
{
protected:
    ///
    ulong dev;
    ///
    bool broadcastAnswer;
    ///
    ulong broadcastDevId = 0;

    override Reaction checkDeviceNumber(ulong dn)
    {
        if (dn == dev) return Reaction.processAndAnswer;
        else if (dn == broadcastDevId)
        {
            if (broadcastAnswer)
                return Reaction.processAndAnswer;
            else
                return Reaction.onlyProcessMessage;
        }
        else return Reaction.none;
    }

public:
    ///
    this(ulong dev, Backend be, void delegate(Duration) sf=null)
    {
        super(be, sf);
        this.dev = dev;
        broadcastAnswer = false;
    }

    /++ Example:
        ---
        slave.func[FuncCode.readInputRegisters] = (m)
        {
            auto origStart = slave.backend.unpackT!ushort(m.data[0..2]);
            auto count = slave.backend.unpackT!ushort(m.data[2..4]);

            if (count == 0 || count > 125) return slave.illegalDataValue;
            if (count > dataTable.length) return slave.illegalDataValue;
            ptrdiff_t start = origStart - START_DATA_REG;
            if (start >=  table.length || start < 0)
                return slave.illegalDataAddress;

            return slave.packResult(cast(ubyte)(count*2), dataTable[start..start+count]);
        };
        ---
     +/
    Function[ubyte] func;

    override MsgProcRes onMessage(ref const Message m)
    {
        if (m.fnc in func) return func[m.fnc](m);
        return illegalFunction;
    }
}

///
deprecated("use ModbusSingleSlave")
alias ModbusSlave = ModbusSingleSlave;

unittest
{
    auto mb = new ModbusSingleSlave(1, new RTU(nullConnection));
    import std.range;
    import std.algorithm;
    mb.packResult(iota(cast(ubyte)10));
    
    assert(equal((cast(ubyte[])(mb.mBuffer[]))[0..10], iota(10)));
}

/++ Multiple devices modbus slave
 +/
class ModbusMultiSlave : ModbusSlaveBase
{
protected:
    override Reaction checkDeviceNumber(ulong dn)
    { return dn in func ? Reaction.processAndAnswer : Reaction.none; }

public:
    ///
    this(Backend be, void delegate(Duration) sf=null) { super(be, sf); }

    ///
    Function[ubyte][ulong] func;

    override MsgProcRes onMessage(ref const Message m)
    {
        // onMessage not call if reaction is none
        if (m.fnc in func[m.dev])
            return func[m.dev][m.fnc](m);
        return illegalFunction;
    }
}