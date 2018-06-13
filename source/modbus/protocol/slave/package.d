///
module modbus.protocol.slave;

public import modbus.protocol.slave.slave;
public import modbus.protocol.slave.model;
public import modbus.protocol.slave.device;

version (unittest) package(modbus):

import modbus.ut;

unittest
{
    mixin(mainTestMix);

    ut!fiberVirtualPipeBasedTest();

    auto cp = getPlatformComPipe(BUFFER_SIZE);

    if (cp is null)
    {
        stderr.writeln(" platform doesn't support real test");
        return;
    }

    stderr.writefln(" port source `%s`\n", cp.command);
    try cp.open();
    catch (Exception e) stderr.writeln(" can't open com pipe: ", e.msg);
    scope (exit) cp.close();
    stderr.writefln(" pipe ports: %s <=> %s", cp.ports[0], cp.ports[1]);

    ut!fiberSerialportBasedTest(cp.ports);
}

void fiberVirtualPipeBasedTest()
{
    auto con = virtualPipeConnection(256, "test");
    baseModbusTest!RTU(con[0], con[1]);
    baseModbusTest!TCP(con[0], con[1]);
}

void fiberSerialportBasedTest(string[2] ports)
{
    enum spmode = "8N1";

    import std.typecons : scoped;
    import serialport;
    import modbus.connection.rtu;

    auto p1 = scoped!SerialPortFR(ports[0], spmode);
    auto p2 = scoped!SerialPortFR(ports[1], spmode);
    p1.flush();
    p2.flush();

    alias SPC = SerialPortConnection;

    baseModbusTest!RTU(new SPC(p1), new SPC(p2));
    baseModbusTest!TCP(new SPC(p1), new SPC(p2));
}

void baseModbusTest(Be: Backend)(Connection masterCon, Connection slaveCon, Duration rtm=500.msecs)
{
    enum DN = 13;
    testPrintf!"BE: %s"(Be.classinfo.name);

    enum dln = TestModbusSlaveDevice.Data.sizeof / 2;
    ushort[] origin = void;
    TestModbusSlaveDevice.Data* originData;

    bool finish;

    void mfnc()
    {
        auto master = new ModbusMaster(new Be, masterCon);
        masterCon.readTimeout = rtm;
        Fiber.getThis.yield();
        auto dt = master.readInputRegisters(DN, 0, dln);
        assert( equal(origin, dt) );
        assert( equal(origin[2..4], master.readHoldingRegisters(DN, 2, 2)) );

        master.writeMultipleRegisters(DN, 2, [0xBEAF, 0xDEAD]);
        assert((*originData).value2 == 0xDEADBEAF);
        master.writeSingleRegister(DN, 15, 0xABCD);
        assert((*originData).usv[1] == 0xABCD);

        finish = true;
    }

    void sfnc()
    {
        auto device = new TestModbusSlaveDevice(DN);
        originData = &device.data;

        auto model = new MultiDevModbusSlaveModel;
        model.devices ~= device;

        auto slave = new ModbusSlave(model, new Be, slaveCon);
        Fiber.getThis.yield();
        while (!finish)
        {
            origin = cast(ushort[])((cast(void*)&device.data)[0..dln*2]);
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
            work = false;
    }
}