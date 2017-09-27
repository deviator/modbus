///
module modbus.protocol;

import std.bitmanip : BitArray;
import std.exception : enforce;
import std.datetime;
import std.conv : to;

version (modbus_verbose)
    public import std.experimental.logger;

import modbus.exception;
import modbus.connection;
import modbus.backend;
import modbus.types;
import modbus.func;

package enum MAX_BUFFER = 260;

///
class Modbus
{
protected:
    void[MAX_BUFFER] buffer;

    Connection con;
    Backend be;

    void delegate(Duration) sleepFunc;

    void sleep(Duration dur)
    {
        import core.thread;

        if (sleepFunc !is null) sleepFunc(dur);
        else
        {
            if (auto fiber = Fiber.getThis)
            {
                auto dt = StopWatch(AutoStart.yes);
                while (dt.peek.to!Duration < dur)
                    fiber.yield();
            }
            else Thread.sleep(dur);
        }
    }

public:

    ///
    this(Connection con, Backend be, void delegate(Duration) sf=null)
    {
        this.con = enforce(con, modbusException("connection is null"));
        this.be = enforce(be, modbusException("backend is null"));
        this.sleepFunc = sf;
    }

    ///
    Duration writeTimeout=10.msecs;
    /// time for waiting message
    Duration readTimeout=1.seconds;

    ///
    Duration writeStepPause = (cast(ulong)(1e7 * 10 / 9600.0)).hnsecs;

    /++ Write to serial port

        Params:
            dev = modbus device address (number)
            fnc = function number
            args = writed data in native endian
     +/
    const(void)[] write(Args...)(ulong dev, ubyte fnc, Args args)
    {
        auto buf = be.buildMessage(buffer, dev, fnc, args);

        size_t cnt = con.write(buf);
        if (cnt == buf.length) return buf;

        auto dt = StopWatch(AutoStart.yes);
        while (cnt != buf.length)
        {
            cnt += con.write(buf[cnt..$]);
            this.sleep(writeStepPause);
            if (dt.peek.to!Duration > writeTimeout)
                throw modbusTimeoutException("write", dev, fnc, writeTimeout);
        }

        return buf;
    }
}

///
class ModbusMaster : Modbus
{
    ///
    this(Connection con, Backend be, void delegate(Duration) sf=null)
    { super(con, be, sf); }

    /// approx 1 byte (10 bits) on 9600 speed
    Duration readStepPause = (cast(ulong)(1e6/96.0)).hnsecs;

    /++ Read from serial port

        Params:
            dev = modbus device address (number)
            fnc = function number
            bytes = expected response length in bytes

        Returns:
            result in big endian
     +/
    const(void)[] read(ulong dev, ubyte fnc, size_t bytes)
    {
        size_t mustRead = bytes + be.notMessageDataLength;
        size_t cnt = 0;
        Message msg;
        try
        {
            auto step = be.minMsgLength;
            auto dt = StopWatch(AutoStart.yes);
            import std.stdio;
            RL: while (cnt <= mustRead)
            {
                auto tmp = con.read(buffer[cnt..cnt+step]);
                cnt += tmp.length;
                if (tmp.length) step = 1;
                auto res = be.parseMessage(buffer[0..cnt], msg);
                with (Backend.ParseResult) FS: final switch(res)
                {
                    case success:
                        if (cnt == mustRead) break RL;
                        else throw readDataLengthException(dev, fnc, mustRead, cnt);
                    case errorMsg: break RL;
                    case uncomplete: break FS;
                    case checkFail:
                        if (cnt == mustRead) throw checkFailException(dev, fnc);
                        else break FS;
                }
                this.sleep(readStepPause);
                if (dt.peek.to!Duration > readTimeout)
                    throw modbusTimeoutException("read", dev, fnc, readTimeout);
            }

            version (modbus_verbose)
                if (res.dev != dev)
                    .warningf("receive from unexpected device %d (expect %d)",
                                    res.dev, dev);
            
            if (msg.fnc != fnc)
                throw functionErrorException(dev, fnc, msg.fnc, (cast(ubyte[])msg.data)[0]);

            if (msg.data.length != bytes)
                throw readDataLengthException(dev, fnc, bytes, msg.data.length);

            return msg.data;
        }
        catch (ModbusDevException e)
        {
            e.readed = buffer[0..cnt];
            throw e;
        }
    }

    /++ Write and read to modbus

        Params:
            dev = slave device number
            fnc = called function number
            bytes = expected bytes for reading
            args = sending data
        Returns:
            result in big endian
     +/
    const(void)[] request(Args...)(ulong dev, ubyte fnc, size_t bytes, Args args)
    {
        auto tmp = write(dev, fnc, args);
        void[MAX_BUFFER] writed = void;
        writed[0..tmp.length] = tmp[];

        try return read(dev, fnc, bytes);
        catch (ModbusDevException e)
        {
            e.writed = writed[0..tmp.length];
            throw e;
        }
    }

    /// function number 0x1 (1)
    const(BitArray) readCoils(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        return const(BitArray)(cast(void[])request(dev, 1, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    /// function number 0x2 (2)
    const(BitArray) readDiscreteInputs(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        return const(BitArray)(cast(void[])request(dev, 2, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    private alias be2na = bigEndianToNativeArr;

    /++ function number 0x3 (3)
        Returns: data in native endian
     +/ 
    const(ushort)[] readHoldingRegisters(ulong dev, ushort start, ushort cnt)
    {
        //if (cnt >= 125) throw modbusException("very big count");
        return be2na(cast(ushort[])request(dev, 3, 1+cnt*2, start, cnt)[1..$]);
    }

    /++ function number 0x4 (4)
        Returns: data in native endian
     +/ 
    const(ushort)[] readInputRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        return be2na(cast(ushort[])request(dev, 4, 1+cnt*2, start, cnt)[1..$]);
    }

    /// function number 0x5 (5)
    void writeSingleCoil(ulong dev, ushort addr, bool val)
    { request(dev, 5, 4, addr, cast(ushort)(val ? 0xff00 : 0x0000)); }

    /// function number 0x6 (6)
    void writeSingleRegister(ulong dev, ushort addr, ushort value)
    { request(dev, 6, 4, addr, value); }

    /// function number 0x10 (16)
    void writeMultipleRegisters(ulong dev, ushort addr, const(ushort)[] values)
    {
        if (values.length >= 125) throw modbusException("very big count");
        request(dev, 16, 4, addr, cast(ushort)values.length,
                    cast(byte)(values.length*2), values);
    }
}

///
class ModbusSlave : Modbus
{
protected:
    ulong dev;
    size_t readed;
    StopWatch dt;
    bool broadcastAnswer;

public:
    ///
    this(ulong dev, Connection con, Backend be, void delegate(Duration) sf=null)
    {
        super(con, be, sf);
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
        switch (m.fnc)
        {
            case 1: return onReadCoils(
                be.unpackT!ushort(m.data[0..us]),
                be.unpackT!ushort(m.data[us..us*2]));
            case 2: return onReadDiscreteInputs(
                be.unpackT!ushort(m.data[0..us]),
                be.unpackT!ushort(m.data[us..us*2]));
            case 3: return onReadHoldingRegisters(
                be.unpackT!ushort(m.data[0..us]),
                be.unpackT!ushort(m.data[us..us*2]));
            case 4: return onReadInputRegisters(
                be.unpackT!ushort(m.data[0..us]),
                be.unpackT!ushort(m.data[us..us*2]));
            case 5: return onWriteSingleCoil(
                be.unpackT!ushort(m.data[0..us]),
                be.unpackT!ushort(m.data[us..us*2]));
            case 6: return onWriteSingleRegister(
                be.unpackT!ushort(m.data[0..us]),
                be.unpackT!ushort(m.data[us..us*2]));
            case 16:
                auto addr = be.unpackT!ushort(m.data[0..us]);
                auto cnt = be.unpackT!ushort(m.data[us..us*2]);
                auto data = cast(ushort[])(m.data[us*2+1..$]);
                foreach (el; data)
                    el = be.unpackT!ushort(cast(void[])[el]);
                return onWriteMultipleRegister(addr, data);
            default: return illegalFunction;
        }
    }

    void onMessageCallAndSendResult(ref const Message msg)
    {
        typeof(onMessage(msg)) res;
        try
        {
            if (msg.dev == 0)
            {
                res = onMessage(msg);
                if (!broadcastAnswer) return;
            }
            else if (msg.dev != dev) return;
            else res = onMessage(msg);
            write(dev, msg.fnc | (res.error ? 0x80 : 0), res.data);
        }
        catch (Throwable e)
            write(dev, msg.fnc|0x80, FunctionErrorCode.SLAVE_DEVICE_FAILURE);
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
            now_readed = con.read(buffer[readed..$]).length;
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