module modbus.ut;

version (unittest): package:

public
{
    import core.thread;

    import std.array;
    import std.algorithm;
    import std.concurrency;
    import std.conv;
    import std.datetime.stopwatch;
    import std.exception;
    import std.format;
    import std.random;
    import std.range;
    import std.stdio : stderr;
    import std.string;
    import std.random;
    import std.process;
}

enum test_print_offset = "    ";

void testPrint(string s) { stderr.writeln(test_print_offset, s); }
void testPrintf(string fmt="%s", Args...)(Args args)
{ stderr.writefln!(test_print_offset~fmt)(args); }

void ut(alias fnc, Args...)(Args args)
{
    enum name = __traits(identifier, fnc);
    stderr.writefln!" >> run %s"(name);
    fnc(args);
    scope (success) stderr.writefln!" << success %s\n"(name);
    scope (failure) stderr.writefln!" !! failure %s\n"(name);
}

enum mainTestMix = `
    stderr.writefln!"=== start %s test {{{\n"(__MODULE__);
    scope (success) stderr.writefln!"}}} finish %s test ===\n"(__MODULE__);
    scope (failure) stderr.writefln!"}}} fail %s test  !!!"(__MODULE__);
    `;