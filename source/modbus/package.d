module modbus;

public:
import modbus.exception;
import modbus.protocol;

version(withSerialPort)
    import modbus.mbwbe;
else
{
    import modbus.iface;
    import modbus.backend.rtu;
}
