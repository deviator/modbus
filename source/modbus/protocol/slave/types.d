///
module modbus.protocol.slave.types;

import modbus.types;
import modbus.backend;

///
struct Response
{
    ///
    void[] data;
    ///
    bool error;

    static auto fail(T)(T val)
    { return Response(cast(void[])[val], true); }

    /// Response with error code (1)
    enum illegalFunction = fail(FunctionErrorCode.illegalFunction);
    /// Response with error code (2)
    enum illegalDataAddress = fail(FunctionErrorCode.illegalDataAddress);
    /// Response with error code (3)
    enum illegalDataValue = fail(FunctionErrorCode.illegalDataValue);
    /// Response with error code (4)
    enum slaveDeviceFailure = fail(FunctionErrorCode.slaveDeviceFailure);
    /// Response with error code (5)
    enum acknowledge = fail(FunctionErrorCode.acknowledge);
    /// Response with error code (6)
    enum slaveDeviceBusy = fail(FunctionErrorCode.slaveDeviceBusy);
    /// Response with error code (8)
    enum memoryParityError = fail(FunctionErrorCode.memoryParityError);
}

///
interface ResponseWriter
{
    ///
    Backend backend() @property;
    ///
    protected void[] buffer() @property;

    ///
    Response pack(Args...)(Args args)
    {
        size_t idx;
        backend.recursiveAppend(buffer, idx, args);
        return Response(buffer[0..idx]);
    }

    /// improve usability: wrap pack method with sending length of array
    final Response packArray(ushort[] arr)
    {
        auto bc = (cast(void[])arr).length;
        if (bc >= ubyte.max)
            throwModbusException("so big array for pack to message");
        return pack(cast(ubyte)bc, arr);
    }
}