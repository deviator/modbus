## Building

Then you run

    dub build --config=master
    dub build --config=slave

you have 2 files: `example_master` and `example_slave`.

## Prepare env

You need to emulate serial port pipe:

    socat pty,raw,echo=0,link=./master.port pty,raw,echo=0,link=./slave.port

`./master.port` and `./slave.port` are your created virtual serial ports.

As alternative you can use 2 usb->serial converters and connect them.

Example programs must can access to devices:

    sudo chmod 0777 /dev/pts/* # access for all users

## Run

By first you need run slave:
    
    ./example_slave RTU ./slave.port 9600 22

or

    ./example_slave TCP localhost 2000 22

After slave started you can read input registers:

    ./example_master RTU ./master.port 9600 22 4 2 5

or

    ./example_master TCP localhost 2000 22 4 2 5

`2000` is a tcp port, `9600` is a baudrate,
`22` is device number on modbus bus, `4` is a function number,
`2` is start register, `5` is count of registers.
