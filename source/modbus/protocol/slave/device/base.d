///
module modbus.protocol.slave.device.base;

public import modbus.types;
public import modbus.backend;
public import modbus.protocol.slave.types;

///
interface ModbusSlaveDevice
{
    ///
    ulong number() @property;

    ///
    Response onMessage(ref const Message msg, ResponseWriter rw);
}