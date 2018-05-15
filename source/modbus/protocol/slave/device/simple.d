module modbus.protocol.slave.device.simple;

import modbus.protocol.slave.device.base;

class SimpleModbusSlaveDevice : ModbusSlaveDevice
{
protected:
    ulong _number;

public:

    this(ulong numb) { _number = numb; }

    override
    {
        ulong number() @property { return _number; }

        Response onMessage(ref const Message msg, ResponseWriter rw)
        {
            alias FC = FunctionCode;

            ushort[] vals = cast(ushort[])msg.data[0..$/2*2];
            foreach (ref v; vals) v = rw.backend.unpackTT(v);

            switch (msg.fnc)
            {
                case FC.readCoils:
                    return onReadCoils(rw, vals[0], vals[1]);
                case FC.readDiscreteInputs:
                    return onReadDiscreteInputs(rw, vals[0], vals[1]);
                case FC.readHoldingRegisters:
                    return onReadHoldingRegisters(rw, vals[0], vals[1]);
                case FC.readInputRegisters:
                    return onReadInputRegisters(rw, vals[0], vals[1]);
                case FC.writeSingleCoil:
                    return onWriteSingleCoil(rw, vals[0], vals[1]);
                case FC.writeSingleRegister:
                    return onWriteSingleRegister(rw, vals[0], vals[1]);
                case FC.writeMultipleCoils:
                    return onWriteMultipleCoils(rw, vals[0], vals[1..$]);
                case FC.writeMultipleRegisters:
                    return onWriteMultipleRegisters(rw, vals[0], vals[1..$]);
                default:
                    return onOtherFunction(rw, msg.fnc, vals);
            }
        }
    }

    Response onReadCoils(ResponseWriter rw, ushort start, ushort count)
    { return Response.illegalFunction; }

    Response onReadDiscreteInputs(ResponseWriter rw, ushort start, ushort count)
    { return Response.illegalFunction; }

    Response onReadHoldingRegisters(ResponseWriter rw, ushort start, ushort count)
    { return Response.illegalFunction; }

    Response onReadInputRegisters(ResponseWriter rw, ushort start, ushort count)
    { return Response.illegalFunction; }

    Response onWriteSingleCoil(ResponseWriter rw, ushort addr, ushort value)
    { return Response.illegalFunction; }

    Response onWriteSingleRegister(ResponseWriter rw, ushort addr, ushort value)
    { return Response.illegalFunction; }

    Response onWriteMultipleCoils(ResponseWriter rw, ushort addr, ushort[] values)
    { return Response.illegalFunction; }

    Response onWriteMultipleRegisters(ResponseWriter rw, ushort addr, ushort[] values)
    { return Response.illegalFunction; }

    Response onOtherFunction(ResponseWriter rw, ubyte func, ushort[] data)
    { return Response.illegalFunction; }
}