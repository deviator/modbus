module modbus.protocol.slave.device.meta;

import modbus.protocol.slave.device.base;

/// Struct based
class ModbusSlaveDeviceMeta : ModbusSlaveDevice
{
protected:
    ulong _number;

    static struct TableProperty
    {
        ubyte func;
        ushort start;
    }

    /// modbus slave table property
    auto mbstp(ubyte func=FunctionCode.readHoldingRegisters, ushort start=0)
    { return TableProperty(func, start); }

public:

    static struct Specification
    {
        uint address;
        uint size;
        string name;
    }

    this(ulong number) { _number = number; }

    override ulong number() @property { return _number; }

    abstract Response onMessage(ref const Message msg, Backend be, void[] buffer);
    abstract Specification[] describe(ubyte func);

    mixin template ModbusSlaveDeviceMetaInit()
    {
        public override Response onMessage(ref const Message msg, Backend be, void[] buffer)
        {
        }
        
        public override Specification[] describe(ubyte func)
        {
        }
    }
}

//class MyDevice : ModbusSlaveDeviceMeta
//{
//    mixin ModbusSlaveDeviceMetaInit;
//    
//    this(ulong num) { super(num); }
//
//    @mbstp(FunctionCode.readHoldingRegisters, 0)
//    @mbstp(FunctionCode.readInputRegisters, 0)
//    MyData myData() @property { return MyData("hello", 123); }
//
//    @mbstp(FunctionCode.readHoldingRegisters, 100)
//    @mbstp(FunctionCode.readInputRegisters, 100)
//    MyData2 myData2() @property { return MyData2("hello", 123); }
//
//    @mbstp(FunctionCode.writeMultipleRegister, 0)
//    void myData(MyData a) @property { }
//
//    @mbstp(FunctionCode.readCoils, 0)
//    void[] bits(ushort start, ushort count)
//    {
//
//    }
//
//    @mbsfc(0x32)
//}