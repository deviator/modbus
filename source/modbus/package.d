///
module modbus;

public:
import modbus.backend;
import modbus.exception;
import modbus.protocol;
import modbus.facade;
import modbus.connection;

unittest
{
    static import std.bitmanip;
    alias bwrite = std.bitmanip.write;
    alias bread = std.bitmanip.read;

    static class ModbusEmulator
    {
        align(1)
        static struct DeviceData
        {
            align(1):
            ushort[4] simpleRegister; // 0..3
            int intValue; // 4
            float floatValue; // 6
        }

        SpecRules sr;
        DeviceData[size_t] regs;
        ubyte[256] res;
        size_t idx;

        this(SpecRules sr)
        {
            regs[70] = DeviceData([1234, 10405, 12, 42], 3^^12, 3.14);
            regs[1] = DeviceData([2345, 50080, 34, 42], 7^^9, 2.71);
            this.sr = sr;
        }

        size_t write(const(void)[] msg)
        {
            idx = 0;
            auto ubmsg = cast(const(ubyte)[])msg;
            ulong dev;
            ubyte fnc;
            sr.peekDF(ubmsg, dev, fnc);
            ubmsg = ubmsg[sr.deviceTypeSize+1..$];

            if (dev !in regs) return msg.length;

            res[idx..idx+sr.deviceTypeSize] = cast(ubyte[])sr.packDF(dev, fnc)[0..sr.deviceTypeSize];
            idx += sr.deviceTypeSize;

            import std.stdio;
            if (!checkCRC(msg))
                storeFail(fnc, FunctionErrorCode.ILLEGAL_DATA_VALUE);
            else
            {
                bwrite(res[], fnc, &idx);

                switch (fnc)
                {
                    case 4:
                        auto d = (cast(ushort*)(dev in regs))[0..DeviceData.sizeof/2];
                        auto st = bread!ushort(ubmsg);
                        auto cnt = cast(ubyte)bread!ushort(ubmsg);
                        bwrite(res[], cnt, &idx);
                        foreach (i; 0 .. cnt)
                            bwrite(res[], d[st+i], &idx);
                        break;
                    default:
                        storeFail(fnc, FunctionErrorCode.ILLEGAL_DATA_VALUE);
                        break;
                }
            }
            storeCRC();
            readResult = res[0..idx];
            return msg.length;
        }

        ubyte[] readResult;
        void[] read(void[] buffer)
        {
            import std.range;
            auto ubbuf = cast(ubyte[])buffer;
            foreach (i; 0 .. buffer.length)
            {
                if (readResult.empty)
                    return buffer[0..i];
                ubbuf[i] = readResult.front;
                readResult.popFront();
            }
            return buffer;
        }

        void storeFail(ubyte fnc, FunctionErrorCode c)
        {
            bwrite(res[], cast(ubyte)(fnc|0x80), &idx);
            bwrite(res[], cast(ubyte)c, &idx);
        }

        void storeCRC()
        {
            auto crc = crc16(res[0..idx]);
            bwrite(res[], crc[0], &idx);
            bwrite(res[], crc[1], &idx);
        }
    }

    BasicSpecRules sr = new BasicSpecRules;

    auto com = new ModbusEmulator(sr);

    auto mbus = new ModbusMaster(new RTU(new class Connection{
        override:
            size_t write(const(void)[] msg) { return com.write(msg); }
            void[] read(void[] buffer) { return com.read(buffer); }
        }, sr));

    assert(mbus.readInputRegisters(70, 0, 1)[0] == 1234);
    import std.algorithm : equal;
    assert(equal(mbus.readInputRegisters(1, 0, 4), [2345, 50080, 34, 42]));
}

version (unittest)
{
    //version = modbus_verbose;

    import std.stdio;
    import std.datetime;
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
        size_t write(const(void[]) msg)
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
        size_t write(const(void[]) msg)
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
        mm.readTimeout = 200.msecs;

        auto ms = new class ModbusSlave
        {
            ushort[] table;
            this()
            {
                super(1, new RTU(conB, sr));
                table = [123, 234, 345, 456, 567, 678, 789, 890, 901];
            }
        override:
            MsgProcRes onReadHoldingRegisters(ushort start, ushort count)
            {
                version (modbus_verbose)
                {
                    import std.stdio;
                    stderr.writeln("count check fails: ", count == 0 || count > 125);
                    stderr.writeln("start check fails: ", start >= table.length);
                }
                if (count == 0 || count > 125) return illegalDataValue;
                if (start >= table.length) return illegalDataAddress;
                if (start+count >= table.length) return illegalDataAddress;

                return mpr(cast(ubyte)(count*2),
                    table[start..start+count]);
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