# Notes for building this on the Windows/Linux machine

This repo is developed across two machines: a Mac (editing, flashing, research) and a PC
with **Gowin EDA**, which is the only place it can be synthesized — Gowin has no macOS build.
If you are the instance on the PC, this file is for you.

## What to build

Open `fpga/Z80_goauld.gprj` in the Gowin IDE and run synthesis + place & route. Target is a
**GW2AR-18C**, package **QFN88** (Tang Nano 20K).

Put the resulting bitstream at:

```
compiled/msxnano-mistle_tangnano20k.fs
```

and commit it with a message naming the source commit, e.g. *"Update compiled Tang Nano 20k
bitstream (built from `<sha>`)"*. The Mac side flashes from there with `openFPGALoader`.

## Things to watch for in this build

**`fpga/src/usb/menu_rom.vh`** is `` `include``d from inside an `always` block in
`fpga/src/usb/sys_ctrl.v`, and lives in the same directory. If Gowin cannot find it, its
include search path does not cover the source file's own directory — say so rather than
working around it silently, and the include can be changed to an explicit relative path.

That file is the OSD menu, a gzipped XML emitted as a `case` statement. It **replaced a
`$readmemh`** that was the prime suspect for the OSD not working: `$readmemh` resolves its
path against the synthesis working directory, which differs between the Gowin IDE and
`build.tcl`, and a path it cannot resolve yields a silently zero-filled ROM. If you still
have the log from a build **before** commit `a70e68e`, a `$readmemh` warning in it would
confirm that diagnosis — worth a look.

Regenerate it with `fpga/src/usb/make_menu_rom.sh` if `msxnano.xml` changes. Never edit it by
hand.

## Please report the utilisation figure

Nobody has ever recorded one for this core, and it gates most of the roadmap — whether there
is room for MIDI, an OPM, cassette support, and so on. From the place & route report:
**LUT, register and BSRAM usage, plus fMax per clock and any timing violations.** Paste it
back, or commit it as `docs/UTILISATION.md`.

The same author wrote [`gowin-mcp`](https://github.com/Papipapito/gowin-mcp), which turns
Gowin build reports into structured data, if that is easier than reading them by hand.

## Current state

The core builds, boots, browses the SD card and runs games. The DB9 joystick works. Two
things do not: **F12 produces no OSD overlay** (the fix above is a hypothesis awaiting this
rebuild) and **pressing F11 a few times crashes the machine** (cause unknown; upstream v1.9
claims to fix an F11 hang, so a stock upstream build on the same board would establish whose
bug it is).

Full status and the roadmap are in [README.md](README.md). Everything established about the
hardware, the shield, the companion protocol and upstream's quirks is in
[docs/FINDINGS.md](docs/FINDINGS.md) — **read that before re-deriving anything**, it exists
so the same ground is not covered twice.

## Conventions

- **Update the docs in the same commit as the code.** The README's status table and the plan
  items are meant to describe the tree as it actually is. Stale docs have caused real errors
  here, including a BOM that pointed at pins now used by the joystick.
- **No emoji or status icons** in the docs. Plain words.
- Say plainly what is unverified. Verified-by-inspection is not verified-on-hardware, and the
  difference has mattered repeatedly on this project.
