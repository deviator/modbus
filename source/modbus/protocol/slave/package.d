///
module modbus.protocol.slave;

public import modbus.protocol.slave.slave;
public import modbus.protocol.slave.model;
public import modbus.protocol.slave.device;

version (unittest)
{
    import std.stdio;
    import std.array;
    import std.format;

    import modbus.connection;
    import modbus.backend;
    import modbus.protocol.master;

    static struct DeviceData
    {
        align(1):
        int value1;
        float value2;
        char[16] str;
    }

    class TestDevice : SimpleModbusSlaveDevice
    {
        DeviceData data;

        this(ulong number)
        {
            super(number);
            data.value1 = 2;
            data.value2 = 3.1415;
            data.str[] = cast(char)0;
            data.str[0..5] = "hello"[];
        }

        ushort[] buf() @property
        { return cast(ushort[])((cast(void*)&data)[0..DeviceData.sizeof]); }

    override:
        Response onReadInputRegisters(ResponseWriter rw, ushort addr, ushort count)
        {
            if (count > 0x7D || count == 0)
                return Response.illegalDataValue;
            if (addr > buf.length || addr+count > buf.length)
                return Response.illegalDataAddress;
            return rw.packArray(buf[addr..count]);
        }
    }
}

unittest
{
    import core.thread;

    enum DN = 12;

    auto con = virtualPipeConnection(256, "test");

    ushort[] origin = void;

    bool finish;

    void mfnc()
    {
        auto master = new ModbusMaster(new RTU, con[0]);

        con[0].readTimeout = 25.msecs;

        Fiber.getThis.yield();

        import std.algorithm;
        assert( equal(origin, master.readInputRegisters(DN, 0, DeviceData.sizeof / 2)) );

        finish = true;
    }

    void sfnc()
    {
        auto device = new TestDevice(DN);
        origin = cast(ushort[])cast(void[])[device.data];

        auto model = new MultiDevModbusSlaveModel;
        model.devs ~= device;

        auto slave = new ModbusSlave(model, new RTU, con[1]);

        Fiber.getThis.yield();

        while (!finish)
        {
            slave.iterate();
            Fiber.getThis.yield();
        }
    }

    auto mfiber = new Fiber(&mfnc);
    auto sfiber = new Fiber(&sfnc);

    bool work = true;
    int step;
    while (work)
    {
        alias TERM = Fiber.State.TERM;
        if (mfiber.state != TERM) mfiber.call;
        //stderr.writeln(getBuffer());
        if (sfiber.state != TERM) sfiber.call;

        step++;
        //stderr.writeln(getBuffer());
        Thread.sleep(10.msecs);
        if (mfiber.state == TERM && sfiber.state == TERM)
        {
            work = false;
        }
    }
}