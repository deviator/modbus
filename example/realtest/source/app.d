import std.stdio;

import socat;
import simpletest;

void main()
{
    writeln("=== start realtest ===");
    auto e = runSocat();

    simpleTest(e.ports);

    writeln("=== finish realtest ===");
}