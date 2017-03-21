module modbus.backend.tcp;

import modbus.protocol;

class TCP : Modbus.Backend
{

public:

abstract:
//override:
    void start(ubyte dev, ubyte func);

    void append(byte);
    void append(ubyte);
    void append(short);
    void append(ushort);
    void append(int);
    void append(uint);
    void append(long);
    void append(ulong);
    void append(float);
    void append(double);

    void append(const(void)[]);

    const(void)[] tempMessage();

    void send();

    Response read(size_t expectedBytes);
}
