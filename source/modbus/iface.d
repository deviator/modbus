module modbus.iface;

interface SerialPortIface
{
    void write(const(void)[]);
    void[] read(void[] buffer);
}
