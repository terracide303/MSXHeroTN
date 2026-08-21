# Notes from the Windows build machine, for the Mac instance

Read this alongside `docs/UTILISATION.md` (full resource/timing report) and the
top-level `CLAUDE.md` (build instructions for this machine).

## Current bitstream

`msxnano-mistle_tangnano20k.fs` in this folder is built from commit `8e6a5e9`
(Gowin EDA 1.9.11.03, `fpga/build.tcl`, target GW2AR-18C QFN88). Synthesis and
place & route both completed with no errors.

**`clock_54m` passes, but only just: Fmax 54.138 MHz against the 54.000 MHz
constraint** — about 0.25% margin, down sharply from the previous build's
57.049 MHz despite this build containing *less* logic, not more. Zero
negative slack, all six clocks pass, CLS 8977/10368 (87%, essentially flat).
Worth flagging to whoever tests next: this is a real pass, not a fluke, but
the margin is thin enough that a small unrelated change could tip it back
into failing. If a future build regresses `clock_54m` again, don't assume
it's the same congestion story as the earlier `28c916d`/`0cf00b7` saga —
check what actually changed, since margin has been noisy build-to-build in
ways not fully explained by logic size alone.

**The previous build (`b903b2f`) closed timing (57.049 MHz) but showed no
picture at all on hardware** — worse than the build before it, which at
least boot-looped with a flash of picture. Root cause per `69791f9`: routing
the OSD reset through a monostable (the fix in `b903b2f`) stopped the
immediate self-clearing boot loop, but the companion re-runs its init action
(which sets `R=1`) after every reset, so the one-shot pulse retriggered
indefinitely and the machine never got past reset at all. The actual fix in
this build removes the OSD reset wiring entirely — Reset and Cold Boot are
gone from the OSD menu, and Turbo no longer applies via reset (takes effect
on next power cycle instead). **Do not re-add OSD-driven reset wiring** —
both prior attempts (level into `bus_reset_n`, and through a monostable)
broke the machine in different ways, and the commit's own conclusion is that
fixing it properly needs sysctrl held out of the core reset domain with its
own power-on reset, which is a real design decision, not a build-side fix.

Menu XML (`msxnano.xml`) and its generated `.hex` changed to drop the two
menu items — extraction into RAM succeeded with no missing-file warnings in
this build's log. Worth confirming visually that the OSD menu no longer
shows Reset/Cold Boot, and that the machine now boots to a picture and stays
up, before testing anything else. Signed volume, scanlines/aspect/stereo/
second-SCC wiring, and the OSD centring offsets are all still unconfirmed on
hardware per the commit — nothing here changes that.

## Flashing

This machine cannot flash the board — the Tang Nano 20k's onboard Sipeed debug
chip (`VID_349B:PID_6160`) isn't a genuine Gowin cable, and Windows keeps
binding it as a plain serial port rather than exposing a JTAG-capable USB
interface, so neither Gowin's own Programmer nor `openFPGALoader` can open it
from here. Flashing stays on the Mac side with `openFPGALoader`, as before.
