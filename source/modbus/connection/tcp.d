///
module modbus.connection.tcp;

import std.socket;
import std.datetime.stopwatch;
import std.conv : to;
public import std.socket : Address, InternetAddress, Internet6Address;
version (Posix) public import std.socket : UnixAddress;

import modbus.exception;
import modbus.connection.base;

abstract class TcpConnectionBase : AbstractConnection
{
protected:
    TcpSocket _socket;

    void delegate(Duration) sleepFunc;

    ptrdiff_t m_write(Socket s, const(void)[] buf)
    {
        const res = s.send(buf);
        if (res == Socket.ERROR)
            throw modbusException("error while send data to tcp socket");
        return res;
    }

    void[] m_read(Socket s, void[] buf)
    {
        const res = s.receive(buf);
        if (res == Socket.ERROR) return buf[0..0];
        return buf[0..res];
    }

public:

    TcpSocket socket() @property { return _socket; }
}

///
class MasterTcpConnection : TcpConnectionBase
{
    ///
    this(Address addr, void delegate(Duration) sleepFunc=null)
    {
        _socket = new TcpSocket();

        if (sleepFunc !is null)
        {
            this.sleepFunc = sleepFunc;
            _socket.blocking = false;
        }
        else _socket.blocking = true;

        _socket.connect(addr);
    }

override:

    void write(const(void)[] msg)
    {
        if (sleepFunc is null) m_write(_socket, msg);

        size_t written;
        auto sw = StopWatch(AutoStart.yes);
        while (sw.peek < _wtm)
        {
            written += m_write(_socket, msg[written..$]);
            if (written == msg.length) return;
            sleepFunc(1.msecs);
        }
        throw new TimeoutException(socket.to!string);
    }

    void[] read(void[] buf, CanRead cr=CanRead.allOrNothing)
    {
        /// TODO REWORK FOR CAN_READ FLAG
        if (sleepFunc is null) return m_read(_socket, buf);

        size_t readed;
        auto sw = StopWatch(AutoStart.yes);
        while (sw.peek < _rtm)
        {
            readed += m_read(_socket, buf[readed..$]).length;
            if (readed == buf.length) return buf[];
            sleepFunc(1.msecs);
        }
        throw new TimeoutException(socket.to!string);
    }
}

///
class SlaveTcpConnection : TcpConnectionBase
{
    Socket cli;

    ///
    this(Address addr, void delegate(Duration) sleepFunc)
    {
        _socket = new TcpSocket();

        if (sleepFunc !is null)
        {
            this.sleepFunc = sleepFunc;
            _socket.blocking = false;

        }
        else _socket.blocking = true;

        _socket.bind(addr);
        _socket.listen(1);
    }

override:
    void write(const(void)[] msg)
    {
        if (cli is null)
            throw modbusException("no client connected");

        if (sleepFunc is null) m_write(cli, msg);

        size_t written;
        auto sw = StopWatch(AutoStart.yes);
        while (sw.peek < _wtm)
        {
            written += m_write(cli, msg[written..$]);
            if (written == msg.length) return;
            sleepFunc(1.msecs);
        }
        throw new TimeoutException(socket.to!string);
    }

    void[] read(void[] buf, CanRead cr=CanRead.allOrNothing)
    {
        /// TODO REWORK FOR CAN_READ FLAG
        try cli = socket.accept();
        catch (Exception) return buf[0..0];
        if (cli is null) return buf[0..0];

        if (sleepFunc is null) return m_read(cli, buf);

        size_t readed;
        auto sw = StopWatch(AutoStart.yes);
        while (sw.peek < _rtm)
        {
            readed += m_read(_socket, buf[readed..$]).length;
            if (readed == buf.length) return buf[];
            sleepFunc(1.msecs);
        }
        return buf[0..readed];
    }
}