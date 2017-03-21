### Modbus protocol

Library provides modbus wrapper over RTU and TCP (WIP) connections.

`Modbus` not manage your serial port or tcp connection.
They uses through simple interfaces with `read` and `write` methods and
you must close opened connections by yourself.

Simple usage:

```d
import serialport;

auto com = new SerialPort("/dev/ttyUSB0", 19200);

auto mbus = new Modbus(new RTU(new class SerialPortIface{
            override:
                void write(const(void)[] msg) { com.write(msg); }
                void[] read(void[] buffer)
                { return com.read(buffer, 1500.dur!"msecs"); }
            }));

auto registers = mbus.readInputRegisters(device, address, count);
```
##### Be careful: `RTU` and `Modbus` don't know about state of `com` -- don't use `mbus` before closing `com`.
