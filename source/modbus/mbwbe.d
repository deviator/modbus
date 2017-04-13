// modbus with back end
module modbus.mbwbe;

import modbus.protocol;
import modbus.iface;

version(withSerialPort)
{
    public import std.datetime : Duration, dur, hnsecs, nsecs, msecs, seconds;
    public import serialport;

    import modbus.backend.rtu;

    /// Modbus with RTU backend based on existing serial port
    class ModbusRTU : Modbus
    {
    protected:
        SerialPort _com;

        class Iface : SerialPortIface
        {
            override:
            void write(const(void)[] msg)
            { _com.write(msg, writeTimeout); }
            void[] read(void[] buffer)
            { return _com.read(buffer, readTimeout, readFrameGap); }
        }

    public:

        ///
        Duration writeTimeout = 100.msecs,
                 readTimeout = 1.seconds,
                 readFrameGap = 4.msecs;

        ///
        this(SerialPort sp)
        {
            import std.exception : enforce;
            _com = enforce(sp, "serial port is null");
            super(new RTU(new Iface));
        }

        @property
        {
            ///
            SerialPort com() { return _com; }
            ///
            const(SerialPort) com() const { return _com; }
        }

        ~this()
        {
            com.destroy();
        }
    }
}