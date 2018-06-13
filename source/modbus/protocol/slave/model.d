///
module modbus.protocol.slave.model;

import modbus.types;
import modbus.backend;
import modbus.protocol.slave.types;
import modbus.protocol.slave.device;

///
interface ModbusSlaveModel
{
    ///
    enum Reaction
    {
        none, ///
        onlyProcessMessage, ///
        processAndAnswer ///
    }

    ///
    Reaction checkDeviceNumber(ulong dev);

    ///
    Response onMessage(ResponseWriter rw, ref const Message msg);
}

///
class NodeModbusSlaveModel : ModbusSlaveModel
{
    ///
    ModbusSlaveModel[] models;

    override
    {
        Reaction checkDeviceNumber(ulong devNumber)
        {
            foreach (mdl; models)
            {
                const r = mdl.checkDeviceNumber(devNumber);
                if (r != Reaction.none) return r;
            }
            return Reaction.none;
        }

        Response onMessage(ResponseWriter rw, ref const Message msg)
        {
            foreach (mdl; models)
            {
                const r = mdl.checkDeviceNumber(msg.dev);
                if (r != Reaction.none) return mdl.onMessage(rw, msg);
            }
            
            throwModbusException("model not found");
            assert(0,"WTF?");
        }
    }
}

///
class MultiCustomDevModbusSlaveModel(T : ModbusSlaveDevice) : ModbusSlaveModel
{
    ///
    T[] devices;

    override
    {
        Reaction checkDeviceNumber(ulong devNumber)
        {
            foreach (dev; devices)
                if (dev.number == devNumber)
                    return Reaction.processAndAnswer;
            return Reaction.none;
        }

        Response onMessage(ResponseWriter rw, ref const Message msg)
        {
            foreach (dev; devices)
                if (dev.number == msg.dev)
                    return dev.onMessage(rw, msg);
            
            throwModbusException("device not found");
            assert(0,"WTF?");
        }
    }
}

///
alias MultiDevModbusSlaveModel = MultiCustomDevModbusSlaveModel!ModbusSlaveDevice;