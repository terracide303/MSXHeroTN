# Notes from the Windows build machine, for the Mac instance

Read this alongside `docs/UTILISATION.md` (full resource/timing report) and the
top-level `CLAUDE.md` (build instructions for this machine).

## Current bitstream

`msxnano-mistle_tangnano20k.fs` in this folder is built from commit `5da94ae`
(Gowin EDA 1.9.11.03, `fpga/build.tcl`, target GW2AR-18C QFN88). Synthesis and
place & route both completed with no errors.

## Things worth knowing before/while testing on hardware

- **`clock_54m` fails timing**: constraint is 54.000 MHz, actual Fmax is
  53.798 MHz. This is a real violation, not just a close call. It's in the same
  pixel-clock domain (`ex_clk_27m_d`) that `build.tcl` already calls out as
  routing-congested (CLS is at 88% utilisation, the tightest resource in the
  design). If you see pixel-clock-domain flakiness — glitchy video, occasional
  garbage on screen, anything timing-sensitive around the VDP/HDMI path — this
  is the first suspect. Not yet root-caused or fixed on this end; flagging it
  rather than silently patching around it, per the project's own convention.
- **`menu_rom.vh` include resolved without any build.tcl change.** CLAUDE.md
  flagged this as a risk (the include search path only covers `src`, not
  `src/usb` where the file actually lives) — but Gowin's preprocessor appears
  to search the including file's own directory first, so no fix was needed.
  Confirmed no `$readmemh`-style warnings in this build's log either.
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
