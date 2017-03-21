module modbus.func;

import std.exception : enforce;
import std.bitmanip;
import std.traits : isArray, Unqual;
import std.range : ElementType;

version(unittest) import std.algorithm : equal;

auto bigEndianToNativeArr(T)(T[] data)
{
    foreach (ref val; data)
        val = bigEndianToNative!T(cast(ubyte[T.sizeof])
                (cast(ubyte*)&val)[0..T.sizeof]);
    return data;
}

unittest
{
    import std.stdio;
    auto data = cast(immutable(void)[])(cast(ubyte[])[0,0,0,1,0,0,0,2,0,0,0,3]);
    assert(equal(cast(ubyte[])data, [0,0,0,1,0,0,0,2,0,0,0,3]));
    assert(equal(cast(ushort[])data, [0,256,0,512,0,768]));
    assert(equal(bigEndianToNativeArr(cast(int[])data.dup), [int(1),2,3]));
    assert(equal(bigEndianToNativeArr(cast(short[])data.dup), [ushort(0),1,0,2,0,3]));
}
