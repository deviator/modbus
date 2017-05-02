// modbus with back end
module modbus.mbwbe;

import modbus.backend;
import modbus.protocol;

version(Have_serialport)
{
    public import std.datetime : Duration, dur, hnsecs, nsecs, msecs, seconds;
    public import serialport;

    /// Modbus with RTU backend constructs from existing serial port object
    class ModbusRTU : Modbus
    {
    protected:
        SerialPort _com;

        class C : Connection
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
            super(new RTU(new C));
        }

        @property
        {
            ///
            SerialPort com() { return _com; }
            ///
            const(SerialPort) com() const { return _com; }
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

    void delegate() yieldFunc;
    private void yield() { if (yieldFunc !is null) yieldFunc(); }

    class C : Connection
    {
    override:
        void write(const(void)[] msg)
        {
            size_t sent;

            while (sent != msg.length)
            {
                auto res = _socket.send(msg[sent..$]);
                if (res == Socket.ERROR)
                    throw new ModbusException("error while send data to tcp socket");

                sent += res;
                yield();
            }
        }

        void[] read(void[] buffer)
        {
            size_t received;
            ptrdiff_t res = -1;
            while (res != 0)
            {
                res = _socket.receive(buffer[received..$]);
                if (res == Socket.ERROR)
                    throw new ModbusException("error while receive data from tcp socket");

                received += res;
                yield();
            }

            return buffer[0..received];
        }
    }

public:

    ///
    this(Address addr, void delegate() yieldFunc=null)
    {
        _socket = new TcpSocket(addr);

        if (yieldFunc !is null)
        {
            _socket.blocking(false);
            this.yieldFunc = yieldFunc;
        }

        super(new TCP(new C));
    }

    @property
    {
        ///
        TcpSocket socket() { return _socket; }
        ///
        const(TcpSocket) socket() const { return _socket; }
    }

    ~this() { _socket.close(); }
}
