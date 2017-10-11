### Modbus protocol

Library provides modbus wrapper over RTU and TCP connections.
By default using [`serialport`](https://github.com/deviator/serialport) package.

Simple usage:

```d
auto mbus = new ModbusRTUMaster("/dev/ttyUSB0", 19200);
mbus.readTimeout = 2.seconds;
writeln(mbus.readInputRegisters(1, 17, 1));
```

Implemented functions:

* 01 (0x01) `readCoils`
* 02 (0x02) `readDiscreteInputs`
* 03 (0x03) `readHoldingRegisters` (returns `const(ushort)[]` in native endian)
* 04 (0x04) `readInputRegisters` (return in native endian too)
* 05 (0x05) `writeSingleCoil`
* 06 (0x06) `writeSingleRegister`
* 16 (0x10) `writeMultipleRegisters`

If you need other function you can use it directly:

```d
auto res = mbus.request(dev, fnc, expectedDataLength, args);
```

where `args` is compile time variadic arguments, they convert
to big endian by element for sending inside lib. `res` returns
in big endian and you must convert to little endian by yourself.

And if you can test new function welcome to pull requests =)

For tcp connection using `std.socket.TcpSocket`.

```d
auto addr = "device_IP";
ushort port = 502; // or 503
auto mbs = new ModbusTCPMaster(new InternetAddress(addr, port));
writeln(mbs.readInputRegisters(1, 17, 1));
```

`ModbusRTUMaster` and `ModbusTCPMaster` close serial port and
socket in destructors.

You can configure library with custom serialport realization.
For this past `subConfiguration "modbus" "custom"` to your `dub.sdl`
or `"subConfigurations": { "modbus": "custom" }` to your `dub.json`.
In this case you can't use `ModbusRTUMaster`.
`ModbusMaster` don't manage your serial port or tcp connection.
They uses through simple interfaces with `read` and `write` methods and
you must close opened connections by yourself.

Example:

```d
import myserialport;
import modbus;

auto com = new MySerialPort();

auto mbus = new ModbusMaster(new class Connection{
            override:
                void write(const(void)[] msg) { com.write(msg); }
                void[] read(void[] buffer) { return com.read(buffer); }
            }, new RTU());

auto registers = mbus.readInputRegisters(device, address, count);
```