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

    import std.typecons;

    alias MsgProcRes = Tuple!(uint, "error", void[], "data");

    enum void[] _iF = cast(void[])[FunctionErrorCode.ILLEGAL_FUNCTION];
    enum void[] _iDV = cast(void[])[FunctionErrorCode.ILLEGAL_DATA_VALUE];
    enum void[] _iDA = cast(void[])[FunctionErrorCode.ILLEGAL_DATA_ADDRESS];
    enum MsgProcRes illegalFunction = MsgProcRes(true, _iF);
    enum MsgProcRes illegalDataValue = MsgProcRes(true, _iDV);
    enum MsgProcRes illegalDataAddress = MsgProcRes(true, _iDA);

    MsgProcRes mpr(Args...)(Args args)
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
        return MsgProcRes(false, data);
    }

    /// function number 0x1 (1)
    MsgProcRes onReadCoils(ushort start, ushort count)
    { return illegalFunction; }
    /// function number 0x2 (2)
    MsgProcRes onReadDiscreteInputs(ushort start, ushort count)
    { return illegalFunction; }
    /// function number 0x3 (3)
    MsgProcRes onReadHoldingRegisters(ushort start, ushort count)
    { return illegalFunction; }
    /// function number 0x4 (4)
    MsgProcRes onReadInputRegisters(ushort start, ushort count)
    { return illegalFunction; }

    /// function number 0x5 (5)
    MsgProcRes onWriteSingleCoil(ushort addr, ushort val)
    { return illegalFunction; }
    /// function number 0x6 (6)
    MsgProcRes onWriteSingleRegister(ushort addr, ushort val)
    { return illegalFunction; }

    /// function number 0x10 (16)
    MsgProcRes onWriteMultipleRegister(ushort addr, ushort[] vals)
    { return illegalFunction; }

    MsgProcRes onMessage(Message m)
    {
        enum us = ushort.sizeof;
        auto one = be.unpackT!ushort(m.data[0..us]);
        auto two = be.unpackT!ushort(m.data[us..us*2]);
        switch (m.fnc)
        {
            case 1: return onReadCoils(one, two);
            case 2: return onReadDiscreteInputs(one, two);
            case 3: return onReadHoldingRegisters(one, two);
            case 4: return onReadInputRegisters(one, two);
            case 5: return onWriteSingleCoil(one, two);
            case 6: return onWriteSingleRegister(one, two);
            case 16:
                auto data = cast(ushort[])(m.data[us*2+1..$]);
                foreach (ref el; data)
                    el = be.unpackT!ushort(cast(void[])[el]);
                return onWriteMultipleRegister(one, data);
            default: return illegalFunction;
        }
    }

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
            write(dev, msg.fnc | (res.error ? 0x80 : 0), res.data);
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