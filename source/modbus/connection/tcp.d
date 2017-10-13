///
module modbus.connection.tcp;

import std.socket;
public import std.socket : Address, InternetAddress, Internet6Address;
version (Posix) public import std.socket : UnixAddress;

import modbus.exception;
import modbus.connection.base;

///
class MasterTcpConnection : Connection
{
    TcpSocket socket;

    ///
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

///
class SlaveTcpConnection : Connection
{
    TcpSocket socket;
    Socket cli;

    ///
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