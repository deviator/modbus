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
        this(string port, uint baudrate, string mode)
        { this(port, SerialPort.Config(baudrate).set(mode)); }

        ///
        this(string port, string mode)
        { this(port, SerialPort.Config.parse(mode)); }

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

import modbus.connection.tcp;
import std.socket : TcpSocket;

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

version (unittest)
{
    //version = modbus_verbose;

    import std.stdio;
    import std.datetime.stopwatch;
    import std.range;

    class ConT1 : Connection
    {
        string name;
        ubyte[]* wbuf;
        ubyte[]* rbuf;
        this(string name, ref ubyte[] wbuf, ref ubyte[] rbuf)
        {
            this.name = name;
            this.wbuf = &wbuf;
            this.rbuf = &rbuf;
        }
    override:
        size_t write(const(void)[] msg)
        {
            (*wbuf) = cast(ubyte[])(msg.dup);
            version (modbus_verbose)
                stderr.writefln("%s write %s", name, (*wbuf));
            return msg.length;
        }

        void[] read(void[] buffer)
        {
            auto ub = cast(ubyte[])buffer;
            size_t i;
            version (modbus_verbose)
                stderr.writefln("%s read %s", name, (*rbuf));
            for (i=0; i < ub.length; i++)
            {
                if ((*rbuf).empty)
                    return buffer[0..i];
                ub[i] = (*rbuf).front;
                (*rbuf).popFront;
            }
            return buffer[0..i];
        }
    }

    class ConT2 : ConT1
    {
        import std.random;

        this(string name, ref ubyte[] wbuf, ref ubyte[] rbuf)
        { super(name, wbuf, rbuf); }

        void slp(Duration d)
        {
            import core.thread;
            auto dt = StopWatch(AutoStart.yes);
            import std.conv : to;
            while (dt.peek.to!Duration < d) Fiber.yield();
        }

    override:
        size_t write(const(void)[] msg)
        {
            auto l = uniform!"[]"(0, msg.length);
            (*wbuf) ~= cast(ubyte[])(msg[0..l].dup);
            slp(uniform(1, 5).usecs);
            version (modbus_verbose)
                stderr.writefln("%s write %s", name, (*wbuf));
            return l;
        }

        void[] read(void[] buffer)
        {
            auto l = uniform!"[]"(0, (*rbuf).length);
            auto ub = cast(ubyte[])buffer;
            size_t i;
            version (modbus_verbose)
                stderr.writefln("%s read %s", name, (*rbuf));
            for (i=0; i < ub.length; i++)
            {
                if (i > l) return buffer[0..i];
                slp(uniform(1, 5).msecs);
                if ((*rbuf).empty)
                    return buffer[0..i];
                ub[i] = (*rbuf).front;
                (*rbuf).popFront;
            }
            return buffer[0..i];
        }
    }

    void testFunc(CT)()
    {
        ubyte[] chA, chB;

        auto conA = new CT("A", chA, chB);
        auto conB = new CT("B", chB, chA);

        auto sr = new BasicSpecRules;
        auto mm = new ModbusMaster(new RTU(conA, sr));
        mm.writeTimeout = 100.msecs;
        mm.readTimeout = 200.msecs;

        auto ms = new class ModbusSlave
        {
            ushort[] table;
            this()
            {
                super(1, new RTU(conB, sr));
                writeTimeout = 100.msecs;
                table = [123, 234, 345, 456, 567, 678, 789, 890, 901];
                func[FuncCode.readHoldingRegisters] = (Message m)
                {
                    enum us = ushort.sizeof;
                    auto start = be.unpackT!ushort(m.data[0..us]);
                    auto count = be.unpackT!ushort(m.data[us..us*2]);
                    version (modbus_verbose)
                    {
                        import std.stdio;
                        stderr.writeln("count check fails: ", count == 0 || count > 125);
                        stderr.writeln("start check fails: ", start >= table.length);
                    }
                    if (count == 0 || count > 125) return illegalDataValue;
                    if (start >= table.length) return illegalDataAddress;
                    if (start+count >= table.length) return illegalDataAddress;

                    return packResult(cast(ubyte)(count*2),
                        table[start..start+count]);
                };
            }
        };

        import core.thread;

        auto f1 = new Fiber(
        {
            bool thrown;
            try mm.readHoldingRegisters(1, 3, 100);
            catch (FunctionErrorException e)
            {
                thrown = true;
                assert(e.code == FunctionErrorCode.ILLEGAL_DATA_ADDRESS);
            }
            assert (thrown);

            thrown = false;
            try mm.readHoldingRegisters(1, 200, 2);
            catch (FunctionErrorException e)
            {
                thrown = true;
                assert(e.code == FunctionErrorCode.ILLEGAL_DATA_ADDRESS);
            }
            assert (thrown);

            thrown = false;
            try mm.readInputRegisters(1, 200, 2);
            catch (FunctionErrorException e)
            {
                thrown = true;
                assert(e.code == FunctionErrorCode.ILLEGAL_FUNCTION);
            }
            assert (thrown);

            auto data = mm.readHoldingRegisters(1, 2, 3);
            assert (data == [345, 456, 567]);
        });

        auto f2 = new Fiber({
            while (true)
            {
                ms.iterate();
                import std.conv;
                auto dt = StopWatch(AutoStart.yes);
                while (dt.peek.to!Duration < 1.msecs)
                    Fiber.yield();
            }
        });
        while (true)
        {
            if (f1.state == f1.state.TERM) break;
            f1.call();
            f2.call();
        }
    }
}

unittest
{
    testFunc!ConT1();
    testFunc!ConT2();
}