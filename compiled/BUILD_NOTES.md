# Notes from the Windows build machine, for the Mac instance

Read this alongside `docs/UTILISATION.md` (full resource/timing report) and the
top-level `CLAUDE.md` (build instructions for this machine).

## Current bitstream

`msxnano-mistle_tangnano20k.fs` in this folder is built from commit `85729ad`
(Gowin EDA 1.9.11.03, `fpga/build.tcl`, target GW2AR-18C QFN88). Synthesis and
place & route both completed with no errors.

**`clock_54m` closes for real this time: Fmax 56.588 MHz against 54.000 MHz,
zero negative slack confirmed via the TNS table** (not just a passing-looking
Fmax number — see below for why that distinction matters here). All six
clocks pass. CLS 9074/10368 (88%).

This ends a run of three failed builds (`0b3f629`, `aa52343`, `c2fcec4`, all
in `compiled/failed/`) that circled the actual cause without finding it. The
last of those, `c2fcec4`, had the lowest CLS of any build (9008, below the
9054 of the last good build `6389ac0`) and touched nothing in `clk_54m` at
all — yet still failed. That ruled out both "resource count" and "which
domain the change lands in" as the explanation, and pointed at the one path
that had never been restructured: every failing build's worst endpoints were
on `cpu1/RD -> mem1/sdram_*`. The `ram_req`/`ram_read`/`ram_write` chains
feeding `memory_ctrl` (instantiated on `clk_54m` despite its `clk_27m` port
name) were serial `?:` chains up to nine levels deep — one had no real
priority to preserve (every branch just returned its own condition, an OR
written the long way), the other had nine branches all returning the
identical value. Flattened to balanced OR trees, exact by construction since
every term is one bit wide, verified across all 544 input combinations of
the compiled configuration with zero mismatches.

**Persistence (from `db4ac25`) and the reverted autofire (from `c2fcec4`)
both ride along unchanged in this build** — `c2fcec4` already proved
persistence wasn't the cause, so nothing there needs re-testing. Same OSD
reset/Cold Boot fix, centring correction and MSXHero rename as `6389ac0`;
the new thing to confirm on hardware specifically is that settings actually
persist across power cycles (volume, DB9 port, autofire — though autofire's
rate control is gone from the menu, fixed at ~10 Hz) and that Boot-in-Turbo
now works.

**`clock_54m` passes with a healthy margin again: Fmax 56.973 MHz against the
54.000 MHz constraint**, zero negative slack, all six clocks pass. CLS ticked
up slightly to 9054/10368 (88%, from 87%). This is a real recovery from the
previous build's thin 54.138 MHz — five commits landed together this round,
so no single one is isolated as the reason margin came back, but nothing
here looks fragile.

**Reset and Cold Boot are back, and this time by fixing the actual cause**
(`c52c1ac`), not by retrying either of the two approaches that already broke
the machine (level into `bus_reset_n` -> boot loop; through a monostable ->
no picture). `fpga_companion` — which holds sysctrl, and therefore the OSD's
values including `system_reset` — was reset from `~bus_reset_n`, the same
core reset the OSD's own reset was driving; hence the earlier self-clearing
problem. The fix resets `fpga_companion` from `~clock_locked` (PLL lock)
instead, the same pattern NanoMig's reference firmware uses, so sysctrl
survives MSX resets and `system_reset` can drive `bus_reset_n` directly as
originally intended. Side effect worth knowing: an MSX reset no longer
resets the companion link or the OSD's own state (previously it did) — that
is now correct behaviour for a peripheral, not a regression, per the commit.
Turbo again applies via `action="reset"` rather than waiting for a power
cycle. **Worth testing on hardware first**: Reset and Cold Boot both work as
expected, and nothing regresses on a plain MSX reset (companion link stays
up, OSD settings survive).

**OSD centring was also corrected** (`093bb4c`) — the previous offsets were
derived from the wrong coordinate system (HDMI encoder porch timings instead
of the VDP's own `hcnt`/`vcnt`), leaving the overlay about 100px right of
centre, matching what the user reported (~8cm off on a ~60cm picture).
Horizontal is recomputed from the VDP's actual constants; vertical was left
alone since it wasn't reported as off, though the commit flags it as
possibly needing the same fix later. Worth confirming the overlay is now
visually centred, especially horizontally.

**Menu ROM was regenerated for both a full English translation and a rename**
(`ac9e539`, `2bd2e32`): boot menu and OSD both now read "MSXHero v1.0"
instead of "MSXnano", every user-facing string is in English (status bar,
help screen, launch/mount/error screens), and the WiFi entry is gone from
the menu since it's compiled out on this fork and previously led to a dead
configuration screen. `msxnano_xml` (OSD) and the boot menu's own ROM both
extracted/loaded cleanly, no missing-file or size warnings in this build's
log — worth visually confirming text renders correctly and nothing got cut
off, since several strings were fit to fixed column counts.

## Flashing

This machine cannot flash the board — the Tang Nano 20k's onboard Sipeed debug
chip (`VID_349B:PID_6160`) isn't a genuine Gowin cable, and Windows keeps
binding it as a plain serial port rather than exposing a JTAG-capable USB
interface, so neither Gowin's own Programmer nor `openFPGALoader` can open it
from here. Flashing stays on the Mac side with `openFPGALoader`, as before.
