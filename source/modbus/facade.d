/// modbus with back end
module modbus.facade;

import modbus.backend;
import modbus.protocol;

public import std.datetime : Duration, dur, hnsecs, nsecs, msecs, seconds;

import modbus.connection.tcp;
import std.socket : Socket;

import modbus.connection.rtu;

/// ModbusMaster with RTU backend
class ModbusRTUMaster : ModbusMaster
{
protected:
    SerialPortConnection spcom;

public:

    ///
    this(SerialPort sp, SpecRules sr=null)
    {
        spcom = new SerialPortConnection(sp);
        super(new RTU(sr), spcom);
    }

    ///
    inout(SerialPort) port() inout @property { return spcom.port; }
}

/// ModbusSingleSlave with RTU backend
class ModbusRTUSlave : ModbusSlave
{
protected:
    SerialPortConnection spcom;

public:

    ///
    this(ModbusSlaveModel mdl, SerialPort sp, SpecRules sr=null)
    {
        spcom = new SerialPortConnection(sp);
        super(mdl, new RTU(sr), spcom);
    }

    ///
    inout(SerialPort) port() inout @property { return spcom.port; }
}

/// Modbus with TCP backend based on TcpSocket from std.socket
class ModbusTCPMaster : ModbusMaster
{
protected:
    MasterTcpConnection mtc;

public:
    ///
    this(Address addr, SpecRules sr=null)
    {
        mtc = new MasterTcpConnection(addr);
        super(new TCP(sr), mtc);
    }

    ///
    inout(Socket) socket() inout @property { return mtc.socket; }

    ~this() { mtc.socket.close(); }
}

///
//class ModbusTCPSlave : ModbusSlave
//{
//protected:
//    SlaveTcpConnection mtc;
//
//public:
//    ///
//    this(ModbusSlaveModel mdl, Address addr, SpecRules sr=null)
//    {
//        mtc = new SlaveTcpConnection(addr);
//        super(mdl, new TCP(sr), mtc);
//    }
//
//    ///
//    inout(TcpSocket) socket() inout @property { return mtc.socket; }
//
//    ~this() { mtc.socket.close(); }
//}