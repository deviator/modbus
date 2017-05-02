///
module modbus;

public:
import modbus.exception;
import modbus.protocol;
import modbus.mbwbe;
import modbus.backend.connection;

unittest
{
    import modbus.backend.rtu;
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

        DeviceData[2] regs;
        ubyte[256] res;
        size_t idx;

        this()
        {
            regs[0] = DeviceData([1234, 10405, 12, 42], 3^^12, 3.14);
            regs[1] = DeviceData([2345, 50080, 34, 42], 7^^9, 2.71);
        }

        void write(const(void)[] msg)
        {
            idx = 0;
            auto ubmsg = cast(const(ubyte)[])msg;
            auto dev = bread!ubyte(ubmsg);
            auto fnc = bread!ubyte(ubmsg);

            if (dev != 0 && dev != 1) return;

            bwrite(res[], dev, &idx);

            if (!checkCRC(msg))
                storeFail(fnc, FunctionErrorCode.ILLEGAL_DATA_VALUE);
            else
            {
                bwrite(res[], fnc, &idx);
                
                switch (fnc)
                {
                    case 4:
                        auto d = (cast(ushort*)(&regs[dev]))[0..DeviceData.sizeof/2];
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
        }

        void[] read(void[] buffer)
        {
            buffer[0..idx] = res[0..idx];
            return buffer[0..idx];
        }

        void storeFail(ubyte fnc, FunctionErrorCode c)
        {
            bwrite(res[], cast(ubyte)(fnc|0xF0), &idx);
            bwrite(res[], cast(ubyte)c, &idx);
        }

        void storeCRC()
        {
            auto crc = crc16(res[0..idx]);
            bwrite(res[], crc[0], &idx);
            bwrite(res[], crc[1], &idx);
        }
    }

    auto com = new ModbusEmulator;

    auto mbus = new Modbus(new RTU(new class Connection{
        override:
            void write(const(void)[] msg) { com.write(msg); }
            void[] read(void[] buffer) { return com.read(buffer); }
        }));

    assert(mbus.readInputRegisters(0, 0, 1)[0] == 1234);
    assert(equal(mbus.readInputRegisters(1, 0, 4), [2345, 50080, 34, 42]));
}