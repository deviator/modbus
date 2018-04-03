import std.stdio;

import socat;
import simpletest;
import multidevtest;

void main()
{
    writeln("=== start realtest ===");
    auto e = runSocat();

    simpleTest(e.ports);
    multiDevTest(e.ports);

    writeln("=== finish realtest ===");
}