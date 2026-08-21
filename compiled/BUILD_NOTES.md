# Notes from the Windows build machine, for the Mac instance

Read this alongside `docs/UTILISATION.md` (full resource/timing report) and the
top-level `CLAUDE.md` (build instructions for this machine).

## Current bitstream

`msxnano-mistle_tangnano20k.fs` in this folder is built from commit `b903b2f`
(Gowin EDA 1.9.11.03, `fpga/build.tcl`, target GW2AR-18C QFN88). Synthesis and
place & route both completed with no errors.

**`clock_54m` still closes comfortably: Fmax 57.049 MHz against 54.000 MHz**,
zero negative slack anywhere, all six clock domains pass, CLS 8993/10368
(87%). This is a rebuild on top of the previous timing-closing commit
(`ca77609`), carrying a real functional fix rather than a timing change.

**The previous build (`ca77609`, pushed as this folder's bitstream earlier
today) did not boot** — the user reported it flashed and showed the MSX
screen briefly before resetting, over and over. Root cause per `6bf45e1`:
the OSD reset wiring (from `1911c67`) let `system_reset` (in sysctrl, inside
`fpga_companion`) drive `bus_reset_n`, which resets `fpga_companion` itself —
so asserting reset cleared the very register asserting it, releasing reset,
which re-entered the loop. The companion's own startup sequence (`R=1` on
init, `R=0` on ready) hit this on every boot, not intermittently. Fixed by
routing the OSD reset through the same fixed-length monostable pulse already
used for `config_reset`, so sysctrl clearing itself mid-pulse no longer
shortens it. This is a genuine functional bug fix, unrelated to the timing
work — worth flashing and confirming the machine now boots and stays up
before testing anything else.

Nothing about the `cpu_din` mux tree restructure (the thing that closed
timing, see `ca77609`/`12444a6`) changed in this build.

## Flashing

This machine cannot flash the board — the Tang Nano 20k's onboard Sipeed debug
chip (`VID_349B:PID_6160`) isn't a genuine Gowin cable, and Windows keeps
binding it as a plain serial port rather than exposing a JTAG-capable USB
interface, so neither Gowin's own Programmer nor `openFPGALoader` can open it
from here. Flashing stays on the Mac side with `openFPGALoader`, as before.
