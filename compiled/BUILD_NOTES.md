# Notes from the Windows build machine, for the Mac instance

Read this alongside `docs/UTILISATION.md` (full resource/timing report) and the
top-level `CLAUDE.md` (build instructions for this machine).

## Branch note

This repo now splits `main` (only advances once a build is verified on
hardware) from `dev` (where build-machine work happens). `85729ad` — the
SDRAM-sequencer fix below — **was verified on hardware**, is tagged
`known-good-85729ad`-equivalent (check `git tag` for the exact name) and
pinned in `compiled/known-good/`, which this machine never writes to. `main`
now points at it. The bitstream below is built from `dev`, one commit past
that, and is **not yet verified on hardware**.

## Current bitstream (on `dev`, not yet hardware-verified)

`msxnano-mistle_tangnano20k.fs` in this folder is built from commit `25f80b8`
on `dev` (Gowin EDA 1.9.11.03, `fpga/build.tcl`, target GW2AR-18C QFN88).
Synthesis and place & route both completed with no errors.

Fixes a real bug found when `85729ad` was tested on hardware: **the machine
booted muted and stayed muted after saving.** `config_sig[5]` (volume) is
latched in the same cycle `config_init` reads it while seeding settings from
flash, one cycle before that byte is actually valid — so every boot read a
stale `8'd0` and seeded volume to zero, silently, since the old validity
test (bit 7 clear) accepted the stale zero as legitimate. Scanlines (byte 2)
landed earlier and were unaffected, which is why they already persisted
correctly. Fixed by seeding one cycle later and tightening the marker to
`[7:6] == 01`, rejecting both an erased `0xFF` and a stale `0x00`.

**`clock_54m` still passes, but the margin thinned noticeably: Fmax 54.306 MHz
against 54.000 MHz (was 56.588 MHz in `85729ad`), zero negative slack
confirmed.** The commit describes this as a `clk_27m`-only change "nowhere
near the paths that were failing," and explicitly asked for the margin to be
reported if it moved — it did move, by a meaningful amount, from a change
that shouldn't have touched the critical domain. Worth flagging plainly
rather than assuming it's noise, per the commit's own request. All other
clocks pass comfortably; CLS 9069/10368 (88%).

**Worth confirming on hardware specifically**: volume now persists correctly
across power cycles (previously silently reset to mute on every boot), and
nothing else regressed. Once confirmed, this is the build to fast-forward
`main` to and tag.

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
