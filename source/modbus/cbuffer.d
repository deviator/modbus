module modbus.cbuffer;

import std.exception;

struct CBuffer
{
    private ubyte[] buf;
    private size_t s, e;

    private this(inout(ubyte)[] buf, size_t s, size_t e) pure inout
    {
        this.buf = buf;
        this.s = s;
        this.e = e;
    }

    this(size_t n) { buf = new ubyte[](n+1); }

    invariant
    {
        assert(s >= 0);
        assert(e >= 0);
        assert(s < buf.length);
        assert(e < buf.length);
    }

    @nogc pure
    {
        const @property
        {
            bool empty() { return s == e; }
            bool full() { return e == (buf.length + s - 1) % buf.length; }

            size_t length()
            {
                if (s <= e) return e - s;
                else return buf.length - (s - e);
            }
        }

        void put(ubyte val)
        {
            assert(!full, "no space");
            buf[e] = val;
            e = (e + 1) % buf.length;
        }

        void put(ubyte[] data)
        {
            assert(data.length < buf.length - length, "no space");
            foreach (i, v; data) put(v);
        }

        void clear() { s = e; }

        @property inout 
        {
            ref inout(ubyte) front()
            {
                assert(!empty, "empty");
                return buf[s];
            }

            ref inout(ubyte) back()
            {
                assert(!empty, "empty");
                return buf[e-1];
            }
        }

        void popFront()
        {
            assert(!empty, "empty");
            s = (s + 1) % buf.length;
        }

        void popBack()
        {
            assert(!empty, "empty");
            e = (buf.length + (cast(ptrdiff_t)e) - 1) % buf.length;
        }

        ref inout(ubyte) opIndex(size_t n) inout
        {
            auto idx = (s+n) % buf.length;
            return buf[idx];
        }
    }

    inout(CBuffer) opSlice(size_t a, size_t b) inout
    {
        enforce(a <= b, new Exception("range: a must be <= b"));
        enforce(b-a <= length, new Exception("range: b-a must be <= length"));

        auto idx_s = (s + a) % buf.length;
        auto idx_e = (s + b) % buf.length;

        return inout CBuffer(buf, idx_s, idx_e);
    }

    CBuffer dup() const @property
    { return CBuffer(buf.dup, s, e); }

    ubyte[] getData(size_t a, size_t b) inout
    {
        enforce(a <= b, new Exception("range: a must be <= b"));
        enforce(b-a <= length, new Exception("range: b-a must be <= length"));

        if (a == b) return [];

        auto idx_s = (s + a) % buf.length;
        auto idx_e = (s + b) % buf.length;

        if (idx_s < idx_e) return buf[idx_s..idx_e].dup;
        else return buf[idx_s..$].dup ~ buf[0..idx_e];
    }

    ubyte[] getData() inout { return getData(0, length); }
}

class CBufferCls
{
    CBuffer s;
    alias s this;
    this(size_t n) { s = CBuffer(n); }
}

unittest
{
    auto buf = CBuffer(10);
    assert(buf.empty);
    assert(!buf.full);
    assert(buf.length == 0);
    buf.put(12);
    assert(!buf.empty);
    assert(!buf.full);
    assert(buf.length == 1);
    assert(buf.front == 12);
    assert(buf.back == 12);
    buf.put(cast(ubyte[])[42, 15]);
    assert(buf.length == 3);
    assert(buf.front == 12);
    assert(buf.back == 15);
    buf.popFront();
    assert(buf.length == 2);
    assert(buf.front == 42);
    assert(buf.back == 15);
    buf.popBack();
    assert(buf.length == 1);
    assert(buf.front == 42);
    assert(buf.back == 42);
    assert(buf.s == 1);
    assert(buf.e == 2);
    buf.put(cast(ubyte[])[1,2,3,4,5]);
    assert(!buf.empty);
    assert(!buf.full);
    assert(buf.length == 6);
    assert(buf.s == 1);
    assert(buf.e == 7);
    buf.popFront();
    buf.popFront();
    buf.popFront();
    assert(!buf.empty);
    assert(!buf.full);
    assert(buf.length == 3);
    buf.put(cast(ubyte[])[11,12,13,14]);
    assert(!buf.empty);
    assert(!buf.full);
    assert(buf.length == 7);
    buf.put(cast(ubyte[])[21,22]);
    assert(!buf.empty);
    assert(!buf.full);
    assert(buf.length == 9);
    buf.put(cast(ubyte[])[31]);
    assert(buf.back == 31);
    assert(!buf.empty);
    assert(buf.full);
    assert(buf.length == 10);
    assertThrown!Throwable(buf.put(42));
    buf.popBack;
    assert(buf.back == 22);
    assert(!buf.empty);
    assert(!buf.full);
    assert(buf.length == 9);
    foreach (i; 0 .. 5) buf.popFront;
    assert(buf.back == 22);
    assert(buf.front == 13);
    assert(!buf.empty);
    assert(!buf.full);
    assert(buf.length == 4);
    buf.popFront;
    buf.popFront;
    buf.popBack;
    buf.popBack;
    assert(buf.empty);
    assert(!buf.full);
    assert(buf.length == 0);
    buf.put(cast(ubyte[])[1,2,3,4,5,6,7,8,9,10]);
    assert(!buf.empty);
    assert(buf.full);
    assert(buf.length == 10);
    foreach (i; 0 .. 5) buf.popFront;
    foreach (i; 0 .. 5) buf.popBack;
    assert(buf.empty);
    assert(!buf.full);
    assert(buf.length == 0);
    buf.put(200);
    assert(buf.front == 200);
    assert(buf.back == 200);
    assert(!buf.empty);
    assert(!buf.full);
    assert(buf.length == 1);
    assert(buf.s == 5);
    assert(buf.e == 6);
}

unittest
{
    auto buf = CBuffer(10);
    buf.put(cast(ubyte[])[1,2,3,4,5,6,8,9]);
    foreach (i; 0..7) buf.popFront;
    buf.put(cast(ubyte[])[1,2,3,4,5,6]);
    assert(buf.getData() == [9, 1, 2, 3, 4, 5, 6]);
    auto buf2 = buf.dup;
    foreach (i; 0..5) buf.popFront;
    assert(buf.length == 2);
    assert(buf.front == 5);
    assert(buf.back == 6);
    assert(buf.getData() == [5, 6]);
    foreach (i; 0..5) buf2.popBack;
    assert(buf2.length == 2);
    assert(buf2.front == 9);
    assert(buf2.back == 1);
    assert(buf2.getData() == [9, 1]);
}

unittest
{
    auto buf = CBuffer(10);
    buf.put(cast(ubyte[])[1,2,3,4,5,6,8,9]);
    foreach (i; 0..7) buf.popFront;
    buf.put(cast(ubyte[])[1,2,3,4,5,6]);
    assert(buf.getData() == [9, 1, 2, 3, 4, 5, 6]);
    auto buf2 = buf[2..6];
    assert(buf2.getData() == [2, 3, 4, 5]);
    assert(buf.buf == buf2.buf);
    buf2.clear();
    assert(buf2.empty);
    assert(buf2.length == 0);
    assert(buf2.getData() == []);
    assert(buf.getData() == [9, 1, 2, 3, 4, 5, 6]);
}

unittest
{
    auto buf = CBuffer(10);
    buf.put(cast(ubyte[])[1,2,3,4,5,6,8,9]);
    foreach (i; 0..7) buf.popFront;
    buf.put(cast(ubyte[])[1,2,3,4,5,6]);
    ubyte[] res;
    foreach (v; buf) res ~= v;
    assert(res == [9, 1, 2, 3, 4, 5, 6]);
}

unittest
{
    auto buf = new CBufferCls(10);
    buf.put(cast(ubyte[])[1,2,3,4,5,6,8,9]);
    foreach (i; 0..7) buf.popFront;
    buf.put(cast(ubyte[])[1,2,3,4,5,6]);
    ubyte[] res;
    buf[0] = 12;
    buf[5] = 55;
    assert(buf[0] == 12);
    foreach (v; buf) res ~= v;
    assert(res == [12, 1, 2, 3, 4, 55, 6]);
}