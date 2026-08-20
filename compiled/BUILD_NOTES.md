# Notes from the Windows build machine, for the Mac instance

Read this alongside `docs/UTILISATION.md` (full resource/timing report) and the
top-level `CLAUDE.md` (build instructions for this machine).

## Current bitstream

`msxnano-mistle_tangnano20k.fs` in this folder is built from commit `fb6bea0`
(Gowin EDA 1.9.11.03, `fpga/build.tcl`, target GW2AR-18C QFN88). Synthesis and
place & route both completed with no errors.

## Things worth knowing before/while testing on hardware

- **`clock_54m` timing violation is fixed.** Previous build (from `5da94ae`)
  missed its 54.000 MHz constraint at 53.798 MHz actual. This build hits
  58.929 MHz. Commit `2c35769` moved the F11 turbo-toggle edge detection out
  of the `clk_54m` domain (turbo is now an OSD setting instead) — that alone
  appears to have closed timing on the domain that was failing. Worth
  confirming turbo still works correctly via the OSD once F12 is testable,
  since that path is new.
- **Status magic fix (`e033f53`)**: sysctrl's CMD 0 response changed from
  `0x7c,0x42,0x10` to `0x5c,0x42,0x00` to match what FPGA-Companion's
  `sys_status_is_valid()` actually checks for. Per the commit, without this
  `sys_wait4fpga()` never succeeds and `osd_init()` never runs — so this may
  be what actually gets the OSD (F12) working at all. Worth testing F12 first
  on this build.
- **The menu ROM mechanism changed again**: back to `$readmemh` loading
  `src/usb/msxnano_xml.hex` (a `reg [7:0] msxnano_xml[1024]` array Gowin
  infers as BSRAM), replacing the generated-case-statement `menu_rom.vh` from
  the previous build. Their commit says the case statement cost LUTs the
  design (88% CLS) couldn't spare. The risk flagged earlier — `$readmemh`
  resolving against the synthesis working directory and silently zero-filling
  the ROM if the path doesn't resolve — is still live for this mechanism, but
  this build's log shows no missing-file warnings, `msxnano_xml` was
  successfully extracted as RAM, and I always build via `gw_sh.exe build.tcl`
  from the `fpga/` directory, which is where `src/usb/msxnano_xml.hex`
  resolves correctly from. Still worth confirming the OSD menu text actually
  renders correctly on hardware rather than assuming from the log alone.
- Only the two long-standing PnR warnings show up (`PINFILTER`/module-swept-in-
  optimizing NL0002 messages, and the `TA1132` clock-not-created warning on
  `fpga_companion_inst/mcu/n4_24`) — nothing new introduced by this round of
  changes.

## Flashing

This machine cannot flash the board — the Tang Nano 20k's onboard Sipeed debug
chip (`VID_349B:PID_6160`) isn't a genuine Gowin cable, and Windows keeps
binding it as a plain serial port rather than exposing a JTAG-capable USB
interface, so neither Gowin's own Programmer nor `openFPGALoader` can open it
from here. Flashing stays on the Mac side with `openFPGALoader`, as before.
