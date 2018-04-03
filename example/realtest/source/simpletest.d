module simpletest;

import base;

enum MODEL_REG = 100;

struct Model
{
    int value;
    int[18] arr;
    bool d1, d2, d3;
}

class FMaster : Fiber
{
    Model model1, model2;

    ulong dev;
    ModbusRTUMaster mb;

    this(ulong dev, string port, string mode)
    {
        this.dev = dev;
        mb = new ModbusRTUMaster(port, mode);
        super(&run);
    }

    bool complite;

    void run()
    {
        // one big query
        model1 = (cast(Model[])(mb.readInputRegisters(dev, MODEL_REG, Model.sizeof/2)))[0];

        // many query by one register
        foreach (i; 0 .. Model.sizeof/2)
            (cast(ushort[])((cast(void*)&model2)[0..Model.sizeof]))[i] =
            (cast(ushort[])(mb.readInputRegisters(dev, cast(ushort)(MODEL_REG+i), ushort(1))))[0];

        complite = true;
    }
}

class FSlave : Fiber
{
    Model model;

    ModbusSingleRTUSlave mb;

    ushort[] table() @property
    { return cast(ushort[])cast(void[])[model]; }

    this(ulong dev, string port, string mode)
    {
        mb = new ModbusSingleRTUSlave(dev, port, mode);

        mb.func[ModbusSingleRTUSlave.FuncCode.readInputRegisters] = (m)
        {
            auto ftus = mb.parseMessageFirstTwoUshorts(m);
            auto start = ftus[0];
            auto count = ftus[1];

            if (count == 0 || count > 125) return mb.illegalDataValue;
            if (count > table.length) return mb.illegalDataValue;
            if (start >= MODEL_REG + table.length || start < MODEL_REG)
                return mb.illegalDataAddress;

            return mb.packResult(cast(ubyte)(count*2),
                    table[start-MODEL_REG..start-MODEL_REG+count]);
        };

        model.value = cast(int)uniform(-100, 100);
        foreach (i, ref v; model.arr)
            v = cast(int)uniform(-200, 200);

        super(&run);
    }

    void run()
    {
        while (1)
        {
            mb.iterate;
            yield;
        }
    }
}

void simpleTest(string[2] ports)
{
    auto dev = 42;
    auto mode = "9600:8N1";

    auto slave = new FSlave(dev, ports[0], mode);
    auto master = new FMaster(dev, ports[1], mode);

    bool work = true;
    size_t steps;

    while (work)
    {
        if (master.state != Fiber.State.TERM) master.call;
        if (slave.state != Fiber.State.TERM) slave.call;

        Thread.sleep(1.msecs);

        steps++;
        if (master.complite)
        {
            enforce(master.model1 == slave.model,
                format("diff models 1: \nm: %s \ns: %s", master.model1, slave.model));
            enforce(master.model2 == slave.model,
                format("diff models 2: \nm: %s \ns: %s", master.model2, slave.model));

            work = false;
            writeln("loop steps: ", steps);
        }
    }
}