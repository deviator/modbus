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

    /// time for waiting message
    Duration readTimeout=1.seconds;

    ///
    Duration readStepPause = (cast(ulong)(1e7 * 10 / 9600.0)).hnsecs;

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
            import std.stdio;
            auto dt = StopWatch(AutoStart.yes);
            import std.stdio;
            RL: while (cnt < mustRead)
            {
                auto tmp = con.read(buffer[cnt..cnt+step]);
                cnt += tmp.length;
                step = 1;
                auto res = be.parseMessage(buffer[0..cnt], msg);
                with (Backend.ParseResult) FS: final switch(res)
                {
                    case success:
                        if (cnt == mustRead) break RL;
                        else throw readDataLengthException(dev, fnc, bytes, cnt);
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
        if (cnt >= 125) throw modbusException("very big count");
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

public:
    ///
    this(ulong dev, Connection con, Backend be, void delegate(Duration) sf=null)
    {
        super(con, be, sf);
        this.dev = dev;
    }

    void onMessage(Message msg)
    {

    }

    ///
    void iterate()
    {
        Message res;

        if (res.dev == 0) // broadcast
        {

        }
        else if (res.dev != dev) return; // not for this device
        else
        {

        }
    }
}