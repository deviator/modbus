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
    this(Connection con, Backend be, void delegate(Duration) sf=null)
    { super(con, be, sf); }

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
            RL: while (cnt <= mustRead)
            {
                auto tmp = con.read(buffer[cnt..cnt+step]);
                cnt += tmp.length;
                if (tmp.length) step = 1;
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
                this.sleep(readStepPause);
                if (dt.peek.to!Duration > readTimeout)
                    throw modbusTimeoutException("read", dev, fnc,
                                                    readTimeout);
            }

            version (modbus_verbose)
                if (res.dev != dev)
                    .warningf("receive from unexpected device "~
                                "%d (expect %d)", res.dev, dev);
            
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
        //if (cnt >= 125) throw modbusException("very big count");
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