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
class MultiDevModbusSlaveModel : ModbusSlaveModel
{
    ModbusSlaveDevice[] devs;

    override
    {
        Reaction checkDeviceNumber(ulong devNumber)
        {
            foreach (dev; devs)
                if (dev.number == devNumber)
                    return Reaction.processAndAnswer;
            return Reaction.none;
        }

        Response onMessage(ResponseWriter rw, ref const Message msg)
        {
            foreach (dev; devs)
                if (dev.number == msg.dev)
                    return dev.onMessage(rw, msg);
            
            throwModbusException("device not found");
            assert(0,"WTF?");
        }
    }
}