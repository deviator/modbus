///
module modbus.protocol.master;

import modbus.protocol.base;

///
class ModbusMaster : Modbus
{
    ///
    this(Backend be, Connection con) { super(be, con); }

    /++ Read from connection

        Params:
            dev = modbus device address (number)
            fnc = function number
            bytes = expected response data length in bytes
                    if < 0 any bytes count can be received
        Returns:
            result in big endian
     +/
    const(void)[] read(ulong dev, ubyte fnc, ptrdiff_t bytes)
    {
        import std.datetime.stopwatch : StopWatch, AutoStart;

        size_t minRead = be.aduLength;
        size_t mustRead;

        if (bytes >= 0)
            mustRead = be.aduLength(bytes);
        else
            mustRead = buffer.length;

        Message msg;

        // save timeout for restoring
        const tm = con.readTimeout;
        const cw = StopWatch(AutoStart.yes);

        con.read(buffer[0..minRead]);

        // next read must have less time
        con.readTimeout = tm - cw.peek;
        // restore origin timeout
        scope (exit) con.readTimeout = tm;

        if (be.ParseResult.success != be.parseMessage(buffer[0..minRead], msg))
        {
            if (minRead == mustRead)
                throwCheckFailException(dev, fnc);

            con.read(buffer[minRead..mustRead], bytes < 0 ?
                                   con.CanRead.anyNonZero : con.CanRead.allOrNothing);
            if (be.ParseResult.success != be.parseMessage(buffer[0..mustRead], msg))
                throwCheckFailException(dev, fnc);
        } // else it's error message

        version (modbus_verbose)
            if (msg.dev != dev)
                .warningf("receive from unexpected device "~
                            "%d (expect %d)", msg.dev, dev);
        
        if (msg.fnc != fnc)
            throwFunctionErrorException(dev, fnc,
                cast(FunctionErrorCode)((cast(ubyte[])msg.data)[0]));

        if (bytes > 0 && msg.data.length != bytes)
            throwReadDataLengthException(dev, fnc, bytes, msg.data.length);

        return msg.data;
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
                                   ptrdiff_t bytes, Args args)
    {
        auto tmp = write(dev, fnc, args);

        import core.thread;
        auto dt = 20.msecs;
        auto sw = StopWatch(AutoStart.yes);
        if (auto f = Fiber.getThis)
            while (sw.peek < dt)
                f.yield();
        else Thread.sleep(dt);

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
        if (cnt >= 2000) throwModbusException("very big count");
        return const(BitArray)(cast(void[])request(
                dev, FunctionCode.readCoils,
                1+(cnt+7)/8, start, cnt)[1..$],
                cnt);
    }

    /// 02 (0x02) Read Discrete Inputs
    const(BitArray) readDiscreteInputs(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 2000) throwModbusException("very big count");
        return const(BitArray)(cast(void[])request(
                dev, FunctionCode.readDiscreteInputs,
                1+(cnt+7)/8, start, cnt)[1..$],
                cnt);
    }

    private alias be2na = bigEndianToNativeArr;

    /++ 03 (0x03) Read Holding Registers
        Returns: data in native endian
     +/ 
    const(ushort)[] readHoldingRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throwModbusException("very big count");
        return be2na(cast(ushort[])request(
                dev, FunctionCode.readHoldingRegisters, 1+cnt*2, start, cnt)[1..$]);
    }

    /++ 04 (0x04) Read Input Registers
        Returns: data in native endian
     +/ 
    const(ushort)[] readInputRegisters(ulong dev, ushort start, ushort cnt)
    {
        if (cnt >= 125) throwModbusException("very big count");
        return be2na(cast(ushort[])request(
                dev, FunctionCode.readInputRegisters, 1+cnt*2, start, cnt)[1..$]);
    }

    /// 05 (0x05) Write Single Coil
    void writeSingleCoil(ulong dev, ushort addr, bool val)
    {
        request(dev, FunctionCode.writeSingleCoil, 4, addr,
                cast(ushort)(val ? 0xff00 : 0x0000));
    }
    /// 06 (0x06) Write Single Register
    void writeSingleRegister(ulong dev, ushort addr, ushort value)
    { request(dev, FunctionCode.writeSingleRegister, 4, addr, value); }

    // TODO
    /// 15 (0x0F) Write Multiple Coils
    //void writeMultipleCoils(ulong dev, ushort addr, const BitArray arr)
    //{
    //    if (arr.length >= 2000) throwModbusException("very big count");
    //    request(dev, FunctionCode.writeMultipleCoils, );
    //}

    /// 16 (0x10) Write Multiple Registers
    void writeMultipleRegisters(ulong dev, ushort addr, const(ushort)[] values)
    {
        if (values.length >= 125) throwModbusException("very big count");
        request(dev, FunctionCode.writeMultipleRegisters,
                    4, addr, cast(ushort)values.length,
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
            sr.unpackDF(ubmsg, dev, fnc);
            ubmsg = ubmsg[sr.deviceTypeSize+1..$];

            if (dev !in regs) return msg.length;

            res[idx..idx+sr.deviceTypeSize] = cast(ubyte[])sr.packDF(dev, fnc)[0..sr.deviceTypeSize];
            idx += sr.deviceTypeSize;

            import std.stdio;
            if (!checkCRC(msg))
                storeFail(fnc, FunctionErrorCode.illegalDataValue);
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
                        storeFail(fnc, FunctionErrorCode.illegalDataValue);
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

    auto mbus = new ModbusMaster(new RTU(sr),
    new class Connection {
        override:
            Duration readTimeout() @property { return Duration.zero; }
            Duration writeTimeout() @property { return Duration.zero; }
            void readTimeout(Duration) {}
            void writeTimeout(Duration) {}
            void write(const(void)[] msg) { com.write(msg); }
            void[] read(void[] buffer, CanRead cr=CanRead.allOrNothing)
            { return com.read(buffer); }
        }
    );

    assert(mbus.readInputRegisters(70, 0, 1)[0] == 1234);
    import std.algorithm : equal;
    assert(equal(mbus.readInputRegisters(1, 0, 4), [2345, 50080, 34, 42]));
}
