///
module modbus.types;

package(modbus) enum MAX_BUFFER = 260;

version (modbus_verbose)
    public import std.experimental.logger;

///
struct Message
{
    /// device number
    ulong dev;
    /// function number
    ubyte fnc;
    /// data without changes (BigEndian)
    const(void)[] data;

    const(ubyte)[] ubdata() const @property
    { return cast(const(ubyte)[])data; }
    /// packet number for RTU, transaction id for TCP
    ulong stamp;
}

///
enum FunctionCode : ubyte
{
    readCoils                  = 0x01, /// 01 (0x01)
    readDiscreteInputs         = 0x02, /// 02 (0x02)
    readHoldingRegisters       = 0x03, /// 03 (0x03)
    readInputRegisters         = 0x04, /// 04 (0x04)
    writeSingleCoil            = 0x05, /// 05 (0x05)
    writeSingleRegister        = 0x06, /// 06 (0x06)
    readExceptionStatus        = 0x07, /// 07 (0x07) Serial line only
    diagnostics                = 0x08, /// 08 (0x08) Serial line only
    getCommEventCounter        = 0x0B, /// 11 (0x0B) Serial line only
    writeMultipleCoils         = 0x0F, /// 15 (0x0F)
    writeMultipleRegisters     = 0x10, /// 16 (0x10)
    readFileRecord             = 0x14, /// 20 (0x14)
    writeFileRecord            = 0x15, /// 21 (0x15) 
    maskWriteRegister          = 0x16, /// 22 (0x16)
    readWriteMultipleRegisters = 0x17, /// 23 (0x17)
    readFIFOQueue              = 0x18, /// 24 (0x18)
}

///
enum FunctionErrorCode : ubyte
{
    illegalFunction    = 1, /// 1
    illegalDataAddress = 2, /// 2
    illegalDataValue   = 3, /// 3
    slaveDeviceFailure = 4, /// 4
    acknowledge        = 5, /// 5
    slaveDeviceBusy    = 6, /// 6
    memoryParityError  = 8, /// 8
    gatewayPathUnavailable = 0xA, /// 0xA
    gatewayTargetDeviceFailedToRespond = 0xB, /// 0xB
}
