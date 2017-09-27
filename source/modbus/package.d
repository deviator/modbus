///
module modbus;

public:
import modbus.backend;
import modbus.exception;
import modbus.protocol;
import modbus.facade;
import modbus.connection;
import modbus.backend.specrules;

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

    auto mbus = new ModbusMaster(new class Connection{
        override:
            size_t write(const(void)[] msg) { return com.write(msg); }
            void[] read(void[] buffer) { return com.read(buffer); }
        }, new RTU(sr));

    assert(mbus.readInputRegisters(70, 0, 1)[0] == 1234);
    import std.algorithm : equal;
    assert(equal(mbus.readInputRegisters(1, 0, 4), [2345, 50080, 34, 42]));
}

unittest
{
    auto sr = new BasicSpecRules;
    auto rtu = new RTU(sr);

    import std.array;
    import std.stdio;
    import std.datetime;

    ubyte[] channelA, channelB;

    auto conA = new class Connection
    {
    override:
        size_t write(const(void[]) msg)
        {
            channelA = cast(ubyte[])(msg.dup);
            return msg.length;
        }

        void[] read(void[] buffer)
        {
            auto ub = cast(ubyte[])buffer;
            size_t i;
            for (i=0; i < ub.length; i++)
            {
                if (channelB.empty)
                    return buffer[0..i];
                ub[i] = channelB.front;
                channelB.popFront;
            }
            return buffer[0..i];
        }
    };

    auto conB = new class Connection
    {
    override:
        size_t write(const(void[]) msg)
        {
            channelB = cast(ubyte[])(msg.dup);
            return msg.length;
        }

        void[] read(void[] buffer)
        {
            auto ub = cast(ubyte[])buffer;
            size_t i;
            for (i=0; i < ub.length; i++)
            {
                if (channelA.empty)
                    return buffer[0..i];
                ub[i] = channelA.front;
                channelA.popFront;
            }
            return buffer[0..i];
        }
    };

    auto mm = new ModbusMaster(conA, rtu);
    mm.readTimeout = 200.msecs;

    auto ccc = conB;

    auto ms = new class ModbusSlave
    {
        this() { super(1, ccc, rtu); }
    override:
        MsgProcRes onReadHoldingRegisters(ushort start, ushort count)
        {
            return mpr(cast(void[])(cast(ubyte[])[count*2]) ~
            cast(void[])((cast(ushort[])[1,2,3,4,5,6,7,8,9])[start..start+count]));
        }
    };

    import core.thread;

    auto f1 = new Fiber(
    {
        auto data = mm.readHoldingRegisters(1, 2, 3);
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