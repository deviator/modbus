module modbus.backend.connection;

interface Connection
{
    void write(const(void)[]);
    void[] read(void[] buffer);
}
