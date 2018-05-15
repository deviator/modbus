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

    /// Response with error code
    enum illegalFunction = fail(FunctionErrorCode.illegalFunction);
    /// ditto
    enum illegalDataAddress = fail(FunctionErrorCode.illegalDataAddress);
    /// ditto
    enum illegalDataValue = fail(FunctionErrorCode.illegalDataValue);
    /// ditto
    enum slaveDeviceFailure = fail(FunctionErrorCode.slaveDeviceFailure);
    /// ditto
    enum acknowledge = fail(FunctionErrorCode.acknowledge);
    /// ditto
    enum slaveDeviceBusy = fail(FunctionErrorCode.slaveDeviceBusy);
    /// ditto
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
}