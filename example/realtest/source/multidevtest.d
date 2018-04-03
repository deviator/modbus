module multidevtest;

import base;

enum MODEL_REG = 100;

struct Model
{
    int value;
    int[18] arr;
    bool d1, d2, d3;
    int[4] arr2;
}

class FMaster : Fiber
{
    Model[ulong] model1, model2;

    ulong[] devs;
    ModbusRTUMaster mb;

    this(ulong[] devs, string port, string mode)
    {
        this.devs = devs;
        mb = new ModbusRTUMaster(port, mode);
        super(&run);
    }

    bool complite;

    void run()
    {
        foreach (dev; devs)
        {
            // one big query
            model1[dev] = (cast(Model[])(mb.readInputRegisters(dev, MODEL_REG, Model.sizeof/2)))[0];

            if (dev !in model2) model2[dev] = Model.init;

            // many query by one register
            foreach (i; 0 .. Model.sizeof/2)
                (cast(ushort[])((cast(void*)&(model2[dev]))[0..Model.sizeof]))[i] =
                (cast(ushort[])(mb.readInputRegisters(dev, cast(ushort)(MODEL_REG+i), ushort(1))))[0];
        }

        complite = true;
    }
}

class FSlave : Fiber
{
    Model[ulong] model;

    ModbusMultiRTUSlave mb;

    ushort[] table(ulong dev) @property
    { return cast(ushort[])cast(void[])[model[dev]]; }

    this(ulong[] devs, string port, string mode)
    {
        mb = new ModbusMultiRTUSlave(port, mode);

        foreach (dev; devs)
        {
            mb.func[dev][ModbusSingleRTUSlave.FuncCode.readInputRegisters] = (m)
            {
                auto ftus = mb.parseMessageFirstTwoUshorts(m);
                auto start = ftus[0];
                auto count = ftus[1];

                if (count == 0 || count > 125) return mb.illegalDataValue;
                if (count > table(m.dev).length) return mb.illegalDataValue;
                if (start >= MODEL_REG + table(m.dev).length || start < MODEL_REG)
                    return mb.illegalDataAddress;

                return mb.packResult(cast(ubyte)(count*2),
                        table(m.dev)[start-MODEL_REG..start-MODEL_REG+count]);
            };
        }

        foreach (dev; devs)
        {
            model[dev] = Model.init;
            model[dev].value = cast(int)uniform(-100, 100);
            foreach (i, ref v; model[dev].arr)
                v = cast(int)uniform(-200, 200);
            foreach (i, ref v; model[dev].arr2)
                v = cast(int)uniform(-200, 200);
        }

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

void multiDevTest(string[2] ports)
{
    auto devs = [1UL, 4, 13, 15, 42];
    auto mode = "9600:8N1";

    auto slave = new FSlave(devs, ports[0], mode);
    auto master = new FMaster(devs, ports[1], mode);

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
            foreach (dev; devs)
            {
                enforce(master.model1[dev] == slave.model[dev],
                    format("diff models %d 1: \nm: %s \ns: %s",
                    dev, master.model1[dev], slave.model[dev]));
                enforce(master.model2[dev] == slave.model[dev],
                    format("diff models %d 2: \nm: %s \ns: %s",
                    dev, master.model2[dev], slave.model[dev]));
            }

            work = false;
            writeln("loop steps: ", steps);
        }
    }
}