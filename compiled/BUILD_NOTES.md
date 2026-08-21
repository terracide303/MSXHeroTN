# Notes from the Windows build machine, for the Mac instance

Read this alongside `docs/UTILISATION.md` (full resource/timing report) and the
top-level `CLAUDE.md` (build instructions for this machine).

## Current bitstream

`msxnano-mistle_tangnano20k.fs` in this folder is built from commit `6389ac0`
(Gowin EDA 1.9.11.03, `fpga/build.tcl`, target GW2AR-18C QFN88). Synthesis and
place & route both completed with no errors.

**Two newer builds were attempted and are NOT here** — both missed `clock_54m`,
so the bitstream in this folder is still `6389ac0`.

- `0b3f629` (first compile of `db4ac25` — settings persistence to flash,
  `system_turbo_boot`/`system_autofire` wired up): compiled cleanly (no
  warnings on `config_save_byte` or `af_limit`, the two things flagged as
  worth watching) but Gowin's "Max Frequency Summary" showed 54.367 MHz —
  looks like a pass, but "Total Negative Slack Summary" showed -0.555 ns
  across 6 Setup endpoints. **The two reports can disagree; TNS is the
  authoritative one.**
- `aa52343` (rewrote OSD autofire from a 23-bit comparator to a
  comparator-free free-running counter, aimed at recovering the miss above):
  CLS landed exactly where predicted (9028/10368, below the 9054 target), but
  timing got **worse**, not better — Fmax 50.717 MHz (a real fail this time,
  not a look-alike), TNS -5.172 ns across 17 endpoints, now including the
  `cpu1/RD` -> `mem1/sdram_*` path family from the original `28c916d`
  regression as well as the recurring `IStatus` -> `cpu_din` one. CLS coming
  down while timing got worse means this isn't just a resource-count story —
  something about where the placer landed this specific netlist hurt the
  CPU/memory-controller boundary despite more room overall.

Both kept at `compiled/failed/msxnano-mistle_tangnano20k_<sha>.fs` with full
details in `compiled/failed/README.md` and `docs/UTILISATION.md`. Reported
rather than trimmed further, per `CLAUDE.md` and the file-ownership
convention — this needs the design side's judgement now, not another
build-side attempt.

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
