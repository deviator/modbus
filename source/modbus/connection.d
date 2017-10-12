///
module modbus.connection;

/// Connection for backends
interface Connection
{
    /++ Write data to connection

        Returns:
            writed data length
     +/
    size_t write(const(void)[] data);

    /++ Read data from connection

        Params:
            buffer = allocated buffer for reading

        Returns:
            slice of buffer with readed data
     +/
    void[] read(void[] buffer);
}