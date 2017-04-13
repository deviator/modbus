### Modbus protocol

Library provides modbus wrapper over RTU and TCP (WIP) connections.
By default using `serialport` package.

Simple usage:

```d
auot mbus = new ModbusRTU(new SerialPort("/dev/ttyUSB0", 19200));

mbus.writeTimeout = 100.msecs;
mbus.readTimeout = 2.seconds;
mbus.readFrameGap = 5.msecs; // use for detect end of data pack
```

`ModbusRTU` close serial port in destructor.

You can configure library with custom serialport realization.
For this past `subConfiguration "modbus" "custom"` to your `dub.sdl`
or `"subConfigurations": { "modbus": "custom" }` to your `dub.json`.
In this case `Modbus` don't manage your serial port or tcp connection.
They uses through simple interfaces with `read` and `write` methods and
you must close opened connections by yourself.

Example:

```d
import myserialport;

auto com = new MySerialPort();

auto mbus = new Modbus(new RTU(new class SerialPortIface{
            override:
                void write(const(void)[] msg) { com.write(msg); }
                void[] read(void[] buffer) { return com.read(buffer); }
            }));

auto registers = mbus.readInputRegisters(device, address, count);
```