module modbus.connection.rtu;

public import serialport;

import modbus.exception;
import modbus.connection.base;

///
class SerialPortConnection : Connection
{
protected:
    ///
    SerialPort sp;

public:
    ///
    this(SerialPort sp) { this.sp = sp; }

    ///
    inout(SerialPort) port() inout @property { return sp; }

override:
    @property
    {
        Duration readTimeout() { return sp.readTimeout; }
        Duration writeTimeout() { return sp.writeTimeout; }
        void readTimeout(Duration d) { sp.readTimeout = d; }
        void writeTimeout(Duration d) { sp.writeTimeout = d; }
    }

    void write(const(void)[] msg) { sp.write(msg); }

    void[] read(void[] buf, CanRead cr=CanRead.allOrNothing)
    { return sp.read(buf, cr); }

    void reconnect() { sp.reopen(); }
}