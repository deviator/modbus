///
module modbus.types;

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
}