///
module modbus.protocol.master;

import modbus.protocol.base;

///
class ModbusMaster : Modbus
{
    /// approx 1 byte (10 bits) on 9600 speed
    protected Duration readStepPause() @property
    { return (cast(ulong)(1e6/96.0)).hnsecs; }

    ///
    this(Backend be, void delegate(Duration) sf=null) { super(be, sf); }

    /++ Read from connection

        Params:
            dev = modbus device address (number)
            fnc = function number
            bytes = expected response data length in bytes
        Returns:
            result in big endian
     +/
    const(void)[] read(ulong dev, ubyte fnc, size_t bytes)
    {
        size_t mustRead = be.aduLength(bytes);
        size_t cnt = 0;
        Message msg;
        try
        {
            auto dt = StopWatch(AutoStart.yes);
            RL: while (cnt < mustRead)
            {
                auto tmp = be.connection.read(buffer[cnt..mustRead]);
                if (tmp.length)
                {
                    cnt += tmp.length;
                    auto res = be.parseMessage(buffer[0..cnt], msg);
                    FS: final switch(res) with (Backend.ParseResult)
                    {
                        case success:
                            if (cnt == mustRead) break RL;
                            else throw readDataLengthException(dev,
                                                    fnc, mustRead, cnt);
                        case errorMsg: break RL;
                        case uncomplete: break FS;
                        case checkFail:
                            if (cnt == mustRead)
                                throw checkFailException(dev, fnc);
                            else break FS;
                    }
                }
                if (dt.peek.to!Duration > readTimeout)
                    throw modbusTimeoutException("read", dev, fnc,
                                                    readTimeout);
                this.sleep(readStepPause);
            }

            version (modbus_verbose)
                if (msg.dev != dev)
                    .warningf("receive from unexpected device "~
                                "%d (expect %d)", msg.dev, dev);
            
            if (msg.fnc != fnc)
                throw functionErrorException(dev, fnc, msg.fnc, 
                                        (cast(ubyte[])msg.data)[0]);

            if (msg.data.length != bytes)
                throw readDataLengthException(dev, fnc, bytes,
                                                msg.data.length);

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
            bytes = expected response data bytes
            args = sending data
        Returns:
            result in big endian
     +/
    const(void)[] request(Args...)(ulong dev, ubyte fnc,
                                   size_t bytes, Args args)
    {
        auto tmp = write(dev, fnc, args);

        try return read(dev, fnc, bytes);
        catch (ModbusDevException e)
        {
            e.writed = tmp[];
            throw e;
        }
    }

    /// 01 (0x01) Read Coils
    const(BitArray) readCoils(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        return const(BitArray)(cast(void[])request(
                dev, 1, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    /// 02 (0x02) Read Discrete Inputs
    const(BitArray) readDiscreteInputs(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throw modbusException("very big count");
        return const(BitArray)(cast(void[])request(
                dev, 2, 1+(cnt+7)/8, start, cnt)[1..$], cnt);
    }

    private alias be2na = bigEndianToNativeArr;

    /++ 03 (0x03) Read Holding Registers
        Returns: data in native endian
     +/ 
    const(ushort)[] readHoldingRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        return be2na(cast(ushort[])request(
                dev, 3, 1+cnt*2, start, cnt)[1..$]);
    }

    /++ 04 (0x04) Read Input Registers
        Returns: data in native endian
     +/ 
    const(ushort)[] readInputRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throw modbusException("very big count");
        return be2na(cast(ushort[])request(
                dev, 4, 1+cnt*2, start, cnt)[1..$]);
    }

    /// 05 (0x05) Write Single Coil
    void writeSingleCoil(ulong dev, ushort addr, bool val)
    { request(dev, 5, 4, addr, cast(ushort)(val ? 0xff00 : 0x0000)); }

    /// 06 (0x06) Write Single Register
    void writeSingleRegister(ulong dev, ushort addr, ushort value)
    { request(dev, 6, 4, addr, value); }

    /// 16 (0x10) Write Multiple Registers
    void writeMultipleRegisters(ulong dev, ushort addr, const(ushort)[] values)
    {
        if (values.length >= 125) throw modbusException("very big count");
        request(dev, 16, 4, addr, cast(ushort)values.length,
                    cast(byte)(values.length*2), values);
    }
}

unittest
{
    static import std.bitmanip;
    alias bwrite = std.bitmanip.write;
    alias bread = std.bitmanip.read;

    static class ModbusEmulator
    {
        align(1)
        static struct DeviceData
        {
            align(1):
            ushort[4] simpleRegister; // 0..3
            int intValue; // 4
            float floatValue; // 6
        }

        SpecRules sr;
        DeviceData[ulong] regs;
        ubyte[256] res;
        size_t idx;

        this(SpecRules sr)
        {
            regs[70] = DeviceData([1234, 10405, 12, 42], 3^^12, 3.14);
            regs[1] = DeviceData([2345, 50080, 34, 42], 7^^9, 2.71);
            this.sr = sr;
        }

        size_t write(const(void)[] msg)
        {
            idx = 0;
            auto ubmsg = cast(const(ubyte)[])msg;
            ulong dev;
            ubyte fnc;
            sr.peekDF(ubmsg, dev, fnc);
            ubmsg = ubmsg[sr.deviceTypeSize+1..$];

            if (dev !in regs) return msg.length;

            res[idx..idx+sr.deviceTypeSize] = cast(ubyte[])sr.packDF(dev, fnc)[0..sr.deviceTypeSize];
            idx += sr.deviceTypeSize;

            import std.stdio;
            if (!checkCRC(msg))
                storeFail(fnc, FunctionErrorCode.ILLEGAL_DATA_VALUE);
            else
            {
                bwrite(res[], fnc, &idx);

                switch (fnc)
                {
                    case 4:
                        auto d = (cast(ushort*)(dev in regs))[0..DeviceData.sizeof/2];
                        auto st = bread!ushort(ubmsg);
                        auto cnt = cast(ubyte)bread!ushort(ubmsg);
                        bwrite(res[], cnt, &idx);
                        foreach (i; 0 .. cnt)
                            bwrite(res[], d[st+i], &idx);
                        break;
                    default:
                        storeFail(fnc, FunctionErrorCode.ILLEGAL_DATA_VALUE);
                        break;
                }
            }
            storeCRC();
            readResult = res[0..idx];
            return msg.length;
        }

        ubyte[] readResult;
        void[] read(void[] buffer)
        {
            import std.range;
            auto ubbuf = cast(ubyte[])buffer;
            foreach (i; 0 .. buffer.length)
            {
                if (readResult.empty)
                    return buffer[0..i];
                ubbuf[i] = readResult.front;
                readResult.popFront();
            }
            return buffer;
        }

        void storeFail(ubyte fnc, FunctionErrorCode c)
        {
            bwrite(res[], cast(ubyte)(fnc|0x80), &idx);
            bwrite(res[], cast(ubyte)c, &idx);
        }

        void storeCRC()
        {
            auto crc = crc16(res[0..idx]);
            bwrite(res[], crc[0], &idx);
            bwrite(res[], crc[1], &idx);
        }
    }

    BasicSpecRules sr = new BasicSpecRules;

    auto com = new ModbusEmulator(sr);

    auto mbus = new ModbusMaster(new RTU(new class Connection{
        override:
            size_t write(const(void)[] msg) { return com.write(msg); }
            void[] read(void[] buffer) { return com.read(buffer); }
        }, sr));

    assert(mbus.readInputRegisters(70, 0, 1)[0] == 1234);
    import std.algorithm : equal;
    assert(equal(mbus.readInputRegisters(1, 0, 4), [2345, 50080, 34, 42]));
}
