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
            super(new RTU(spcom, sr));
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
        override void setSleepFunc(void delegate(Duration) f)
        {
            super.setSleepFunc(f);
            spcom.sp.sleepFunc = f;
        }

        ~this() { spcom.sp.destroy(); }
    }
}

import std.socket;
public import std.socket : Address, InternetAddress, Internet6Address;
version (Posix) public import std.socket : UnixAddress;

class MasterTcpConnection : Connection
{
    TcpSocket socket;

    this(Address addr)
    {
        socket = new TcpSocket();
        socket.connect(addr);
        socket.blocking = false;
    }

override:
    size_t write(const(void)[] msg)
    {
        const res = socket.send(msg);
        if (res == Socket.ERROR)
            throw modbusException("error while send data to tcp socket");
        return res;
    }

    void[] read(void[] buffer)
    {
        const res = socket.receive(buffer);
        if (res == Socket.ERROR) return buffer[0..0];
        return buffer[0..res];
    }
}

/// Modbus with TCP backend based on TcpSocket from std.socket
class ModbusTCPMaster : ModbusMaster
{
protected:
    MasterTcpConnection mtc;
public:
    ///
    this(Address addr, SpecRules sr=null)
    {
        mtc = new MasterTcpConnection(addr);
        super(new TCP(mtc, sr));
    }

    ///
    inout(TcpSocket) socket() inout @property { return mtc.socket; }

    ~this() { mtc.socket.close(); }
}

class SlaveTcpConnection : Connection
{
    TcpSocket socket;
    Socket cli;

    this(Address addr)
    {
        socket = new TcpSocket();
        socket.blocking = false;
        socket.bind(addr);
        socket.listen(1);
    }

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
        try cli = socket.accept();
        catch (Exception) return buffer[0..0];
        if (cli is null) return buffer[0..0];
        const res = cli.receive(buffer);
        if (res == Socket.ERROR) return buffer[0..0];
        return buffer[0..res];
    }
}