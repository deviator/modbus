module modbus.msleep;

import core.thread : Fiber, Thread;
import std.datetime.stopwatch : Duration, StopWatch, AutoStart;

void msleep()(Duration d)
{
    if (auto f = Fiber.getThis)
    {
        const sw = StopWatch(AutoStart.yes);
        do f.yield(); while (sw.peek < d);
    }
    else Thread.sleep(d);
}