## RTU

### Building

Then you run

    dub build --config=rtu-master
    dub build --config=rtu-slave

you have 2 files: `example_master` and `example_slave`.

### Prepare env

You need to emulate serial port pipe:

    sudo socat -d -d pty,raw,echo=0 pty,raw,echo=0

`socat` show you output like this:

    2018/03/02 14:25:31 socat[13578] N PTY is /dev/pts/5
    2018/03/02 14:25:31 socat[13578] N PTY is /dev/pts/6
    2018/03/02 14:25:31 socat[13578] N starting data transfer loop with FDs [5,5] and [7,7]
    
`/dev/pts/5` and `/dev/pts/6` are your created virtual serial ports.

As alternative you can use 2 usb->serial converters and connect them.

Example programs must can access to devices:

    sudo chmod 0777 /dev/pts/* # access for all users

### Run

By first you need run slave:
    
    ./example_slave /dev/pts/5 9600 22

After slave started you can read input registers:

    ./example_master /dev/pts/6 9600 22 2 5

Use different names of virtual serial port pipe (`/dev/pts/5` and `/dev/pts/6`).
`9600` is a baudrate, `22` is device number on modbus bus,
`2` is start register, `5` is count of registers.
