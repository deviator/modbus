/// modbus with back end
module modbus.facade;

import modbus.backend;
import modbus.protocol;

version(Have_serialport)
{
    public import std.datetime : Duration, dur, hnsecs, nsecs, msecs, seconds;
    public import serialport;

    /// Modbus with RTU backend constructs from existing serial port object
    class ModbusRTUMaster : ModbusMaster
    {
    protected:
        SerialPort _com;

        class C : Connection { override:
            size_t write(const(void)[] msg) { return _com.write(msg); }
            void[] read(void[] buffer) { return _com.read(buffer); }
        }

    public:

        ///
        this(string port, uint baudrate, StopBits stopbits=StopBits.one,
             Parity parity=Parity.none, DataBits databits=DataBits.data8)
        {
            _com = new SerialPort(port, SerialPort.Config(baudrate,
                                    parity, databits, stopbits));
            super(new C, new RTU);
        }

        ///
        this(string dev, SerialPort.Config cfg, void delegate(Duration) sf, SpecRules sr=null)
        {
            _com = new SerialPort(dev, cfg, sf);
            super(new C, new RTU(sr), sf);
        }

        ///
        this(SerialPort sp, SpecRules sr=null)
        {
            import std.exception : enforce;
            _com = enforce(sp, "serial port is null");
            super(new C, new RTU(sr));
        }

        ///
        void flush()
        {
            try
            {
                void[240] buf = void;
                auto res = com.read(buf);
                version (modbus_verbose)
                    .info("flush ", cast(ubyte[])(res));
            }
            catch (TimeoutException e)
                version (modbus_verbose)
                    .trace("flust timeout");
        }

        inout(SerialPort) com() inout @property { return _com; }

        ///
        auto setSleepFunc(void delegate(Duration) f)
        {
            sleepFunc = f;
            _com.sleepFunc = f;
            return this;
        }

        ~this() { _com.destroy(); }
    }
}

import std.socket;
public import std.socket : Address, InternetAddress, Internet6Address;
version (Posix) public import std.socket : UnixAddress;

/// Modbus with TCP backend based on TcpSocket from std.socket
class ModbusTCP : Modbus
{
protected:
    TcpSocket _socket;

    class C : Connection
    {
    override:
        size_t write(const(void)[] msg)
        {
            const res = _socket.send(msg);
            if (res == Socket.ERROR)
                throw modbusException("error while send data to tcp socket");
            return res;
        }

        void[] read(void[] buffer)
        {
            const res = _socket.receive(buffer);
            if (res == Socket.ERROR)
                throw modbusException("error while receive data from tcp socket");
            return buffer[0..res];
        }
    }

public:

    ///
    this(Address addr, SpecRules sr=null)
    {
        _socket = new TcpSocket(addr);
        _socket.blocking(false);
        super(new C, new TCP(sr));
    }

    ///
    inout(TcpSocket) socket() inout @property { return _socket; }

    ~this() { _socket.close(); }
}