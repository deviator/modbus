///
module modbus.protocol.slave;

import modbus.protocol.base;

///
class ModbusSlave : Modbus
{
protected:
    ///
    ulong dev;
    size_t readed;
    StopWatch dt;
    bool broadcastAnswer;
    ulong broadcastDevId = 0;

public:
    ///
    this(ulong dev, Backend be,
            void delegate(Duration) sf=null)
    {
        super(be, sf);
        this.dev = dev;
        // approx 10 bytes (10 bits) on 9600 speed
        readTimeout = (cast(ulong)(1e7/96.0)).hnsecs;
        broadcastAnswer = false;
    }

    ///
    struct MsgProcRes
    {
        ///
        void[] data;
        ///
        uint error;
        ///
        static auto fail(T)(T val) { return MsgProcRes(cast(void[])[val], true); }
    }

    ///
    alias Function = MsgProcRes delegate(Message);

    ///
    enum FuncCode : ubyte
    {
        readCoils             = 0x1,  /// function number 0x1 (1)
        readDiscreteInputs    = 0x2,  /// function number 0x2 (2)
        readHoldingRegisters  = 0x3,  /// function number 0x3 (3)
        readInputRegisters    = 0x4,  /// 0x4 (4)
        writeSingleCoil       = 0x5,  /// 0x5 (5)
        writeSingleRegister   = 0x6,  /// 0x6 (6)
        writeMultipleRegister = 0x10, /// 0x10 (16)
    }

    ///
    Function[ubyte] func;

    ///
    enum illegalFunction = MsgProcRes.fail(FunctionErrorCode.ILLEGAL_FUNCTION);
    ///
    enum illegalDataValue = MsgProcRes.fail(FunctionErrorCode.ILLEGAL_DATA_VALUE);
    ///
    enum illegalDataAddress = MsgProcRes.fail(FunctionErrorCode.ILLEGAL_DATA_ADDRESS);

    ///
    MsgProcRes packResult(Args...)(Args args)
    {
        void[] data;
        foreach (arg; args)
        {
            import std.traits;
            static if (isArray!(typeof(arg)))
            {
                foreach (e; arg)
                    data ~= be.packT(e);
            }
            else data ~= be.packT(arg);
        }
        return MsgProcRes(data);
    }

    ///
    MsgProcRes onMessage(Message m)
    {
        if (m.fnc in func) return func[m.fnc](m);
        return illegalFunction;

        //enum us = ushort.sizeof;
        //auto one = be.unpackT!ushort(m.data[0..us]);
        //auto two = be.unpackT!ushort(m.data[us..us*2]);
        //switch (m.fnc)
        //{
        //    case 1: return onReadCoils(one, two);
        //    ----------//----------
        //    case 6: return onWriteSingleRegister(one, two);
        //    case 16:
        //        auto data = cast(ushort[])(m.data[us*2+1..$]);
        //        foreach (ref el; data) el = be.unpackTT(el);
        //        return onWriteMultipleRegister(one, data);
        //    default: return illegalFunction;
        //}
    }

    ///
    void onMessageCallAndSendResult(ref const Message msg)
    {
        typeof(onMessage(msg)) res;
        try
        {
            if (msg.dev == broadcastDevId)
            {
                res = onMessage(msg);
                if (!broadcastAnswer) return;
            }
            else if (msg.dev != dev) return;
            else res = onMessage(msg);
            this.write(dev, msg.fnc | (res.error ? 0x80 : 0), res.data);
        }
        catch (Throwable e)
        {
            import std.experimental.logger;
            errorf("%s", e);
            this.write(dev, msg.fnc|0x80,
                    FunctionErrorCode.SLAVE_DEVICE_FAILURE);
        }
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
                onMessageCallAndSendResult(msg);
                readed = 0;
                break;
            case errorMsg: /+ master send error? WTF? +/ break;
            case uncomplete: break;
            case checkFail: break;
        }
    }
}