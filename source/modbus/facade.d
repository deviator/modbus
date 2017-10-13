/// modbus with back end
module modbus.facade;

import modbus.backend;
import modbus.protocol;

version(Have_serialport)
{
    public import std.datetime : Duration, dur, hnsecs, nsecs, msecs, seconds;
    public import serialport;

    ///
    class SerialPortConnection : Connection
    {
        ///
        SerialPort sp;
        ///
        this(SerialPort sp) { this.sp = sp; }
    override:
        ///
        size_t write(const(void)[] msg) { return sp.write(msg); }
        ///
        void[] read(void[] buffer) { return sp.read(buffer); }
    }

    /// Modbus with RTU backend constructs from existing serial port object
    class ModbusRTUMaster : ModbusMaster
    {
    protected:
        ///
        SerialPortConnection spcom;

        override @property
        {
            Duration writeStepPause() { return readStepPause; }
            Duration readStepPause()
            { return (cast(ulong)(1e8 / com.baudRate)).hnsecs; }
        }

    public:

        ///
        this(string port, uint baudrate, StopBits stopbits=StopBits.one,
             Parity parity=Parity.none, DataBits databits=DataBits.data8)
        { this(port, SerialPort.Config(baudrate, parity, databits, stopbits)); }

        ///
        this(string port, SerialPort.Config cfg, void delegate(Duration) sf=null,
            SpecRules sr=null)
        { this(new SerialPort(port, cfg, sf), sf, sr); }

        ///
        this(string port, uint baudrate, void delegate(Duration) sf, SpecRules sr=null)
        { this(new SerialPort(port, baudrate, sf), sf, sr); }

        ///
        this(SerialPort sp, void delegate(Duration) sf=null, SpecRules sr=null)
        {
            spcom = new SerialPortConnection(sp); 
            super(spcom, new RTU(sr));
        }

        ///
        void flush()
        {
            void[240] buf = void;
            auto res = com.read(buf);
            version (modbus_verbose)
                .info("flush ", cast(ubyte[])(res));
        }

        ///
        inout(SerialPort) com() inout @property { return spcom.sp; }

        ///
        auto setSleepFunc(void delegate(Duration) f)
        {
            sleepFunc = f;
            spcom.sp.sleepFunc = f;
            return this;
        }

        ~this() { spcom.sp.destroy(); }
    }
}

import std.socket;
public import std.socket : Address, InternetAddress, Internet6Address;
version (Posix) public import std.socket : UnixAddress;

/// Modbus with TCP backend based on TcpSocket from std.socket
class ModbusTCPMaster : ModbusMaster
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
            if (res == Socket.ERROR) return buffer[0..0];
            return buffer[0..res];
        }
    }

public:

    ///
    this(Address addr, SpecRules sr=null)
    {
        _socket = new TcpSocket();
        _socket.connect(addr);
        _socket.blocking = false;
        super(new C, new TCP(sr));
    }

    ///
    inout(TcpSocket) socket() inout @property { return _socket; }

    ~this() { _socket.close(); }
}

/// Modbus with TCP backend based on TcpSocket from std.socket
class ModbusTCPSlave : ModbusSlave
{
protected:
    TcpSocket _socket;
    Socket cli;

    class C : Connection
    {
    override:
        size_t write(const(void)[] msg)
        {
            if (cli is null) return 0;
            const res = cli.send(msg);
            if (res == Socket.ERROR)
                throw modbusException("error while send data to tcp socket");
            return res;
        }

        void[] read(void[] buffer)
        {
            try cli = _socket.accept();
            catch (Exception) return buffer[0..0];
            if (cli is null) return buffer[0..0];
            const res = cli.receive(buffer);
            if (res == Socket.ERROR) return buffer[0..0];
            return buffer[0..res];
        }
    }

public:

    ///
    this(ulong dev, Address addr, SpecRules sr=null)
    {
        _socket = new TcpSocket();
        _socket.blocking = false;
        _socket.bind(addr);
        _socket.listen(1);
        super(dev, new C, new TCP(sr));
    }

    ///
    inout(TcpSocket) socket() inout @property { return _socket; }

    ~this() { _socket.close(); }
}