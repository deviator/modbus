module modbus.protocol.slave.device.simple;

import modbus.protocol.slave.device.base;

class SimpleModbusSlaveDevice : ModbusSlaveDevice
{
protected:
    ulong _number;
    ushort[0x7D] vals;

public:

    this(ulong numb) { _number = numb; }

    override
    {
        ulong number() @property { return _number; }

        Response onMessage(ResponseWriter rw, ref const Message msg)
        {
            alias FC = FunctionCode;

            auto st = cast(ushort[])msg.data[0..$/2*2];
            auto addr = rw.backend.unpackTT(st[0]);
            auto voc = rw.backend.unpackTT(st[1]);

            auto mltData()
            {
                auto umd = cast(ushort[])msg.data[5..$];
                foreach (i, v; umd) vals[i] = rw.backend.unpackTT(v);
                return vals[0..umd.length];
            }

            switch (msg.fnc)
            {
                case FC.readCoils:
                    return onReadCoils(rw, addr, voc);
                case FC.readDiscreteInputs:
                    return onReadDiscreteInputs(rw, addr, voc);
                case FC.readHoldingRegisters:
                    return onReadHoldingRegisters(rw, addr, voc);
                case FC.readInputRegisters:
                    return onReadInputRegisters(rw, addr, voc);
                case FC.writeSingleCoil:
                    return onWriteSingleCoil(rw, addr, voc);
                case FC.writeSingleRegister:
                    return onWriteSingleRegister(rw, addr, voc);
                case FC.writeMultipleCoils:
                    return onWriteMultipleCoils(rw, addr, mltData);
                case FC.writeMultipleRegisters:
                    return onWriteMultipleRegisters(rw, addr, mltData);
                default:
                    return onOtherFunction(rw, msg.fnc, msg.data);
            }
        }
    }

    Response onReadCoils(ResponseWriter rw, ushort addr, ushort count)
    { return Response.illegalFunction; }

    Response onReadDiscreteInputs(ResponseWriter rw, ushort addr, ushort count)
    { return Response.illegalFunction; }

    Response onReadHoldingRegisters(ResponseWriter rw, ushort addr, ushort count)
    { return Response.illegalFunction; }

    Response onReadInputRegisters(ResponseWriter rw, ushort addr, ushort count)
    { return Response.illegalFunction; }

    Response onWriteSingleCoil(ResponseWriter rw, ushort addr, ushort value)
    { return Response.illegalFunction; }

    Response onWriteSingleRegister(ResponseWriter rw, ushort addr, ushort value)
    { return Response.illegalFunction; }

    Response onWriteMultipleCoils(ResponseWriter rw, ushort addr, const(ushort)[] values)
    { return Response.illegalFunction; }

    Response onWriteMultipleRegisters(ResponseWriter rw, ushort addr, const(ushort)[] values)
    { return Response.illegalFunction; }

    Response onOtherFunction(ResponseWriter rw, ubyte func, const(void)[] data)
    { return Response.illegalFunction; }
}

version (unittest):

class TestModbusSlaveDevice : SimpleModbusSlaveDevice
{
    static struct Data
    {
        align(1):
        uint value1; // 0 - 1
        uint value2; // 2 - 3
        char[16] str; // 4 - 11
        float value3; // 12 - 13
        ushort[12] usv; // 14 - 26
    }

    Data data;

    this(ulong number)
    {
        super(number);
        rndData(data);
    }

    void rndData(ref Data tdd)
    {
        import std.random : uniform;

        tdd.value1 = uniform(0, uint.max);
        tdd.value2 = uniform(0, uint.max);
        tdd.str[] = cast(char)0;
        tdd.str[0..5] = "hello"[];
        tdd.value3 = 3.1415;
        foreach (ref v; tdd.usv)
            v = uniform(ushort(0), ushort.max);
    }

    ushort[] buf() @property
    { return cast(ushort[])((cast(void*)&data)[0..data.sizeof]); }

override:

    Response onReadInputRegisters(ResponseWriter rw, ushort addr, ushort count)
    {
        if (count > 0x7D || count == 0)
            return Response.illegalDataValue;
        if (addr >= buf.length || addr+count > buf.length)
            return Response.illegalDataAddress;
        return rw.packArray(buf[addr..addr+count]);
    }

    Response onReadHoldingRegisters(ResponseWriter rw, ushort addr, ushort count)
    { return onReadInputRegisters(rw, addr, count); }

    Response onWriteSingleRegister(ResponseWriter rw, ushort addr, ushort value)
    {
        if (addr > buf.length)
            return Response.illegalDataAddress;
        buf[addr] = value;
        return rw.pack(addr, value);
    }

    Response onWriteMultipleRegisters(ResponseWriter rw, ushort addr, const(ushort)[] values)
    {
        if (values.length > 0x7D || values.length == 0)
            return Response.illegalDataValue;
        if (addr >= buf.length || addr+values.length > buf.length)
            return Response.illegalDataAddress;
        buf[addr..addr+values.length] = values[];
        return rw.pack(addr, cast(ushort)values.length);
    }
}