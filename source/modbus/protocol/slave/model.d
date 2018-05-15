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
    Response onMessage(ref const Message msg, Backend be);
}

///
class MultiDevModbusSlaveModel : ModbusSlaveModel
{
    void[MAX_BUFFER] buffer;

    static class SRW : ResponseWriter
    {
        Backend be;
        void[] buf;

        this(Backend be, void[] buf)
        {
            this.be = be;
            this.buf = buf;
        }

        override Backend backend() @property { return be; }
        protected override void[] buffer() @property { return buf; }

    }

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

        Response onMessage(ref const Message msg, Backend be)
        {
            foreach (dev; devs)
                if (dev.number == msg.dev)
                {
                    import std.typecons : scoped;
                    auto srw = scoped!SRW(be, buffer[]);
                    return dev.onMessage(msg, srw);
                }
            
            throw modbusException("device not found");
        }
    }
}