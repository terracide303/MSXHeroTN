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

- `fpga/src/usb/msxnano_xml.hex` is loaded by `$readmemh` from `sys_ctrl.v`, with the path
  relative to the synthesis working directory. Regenerate it with
  `fpga/src/usb/make_menu_rom.sh` if `msxnano.xml` changes; never edit it by hand.
- **`clock_54m` misses its constraint** — 53.798 MHz against 54.000. It predates this fork,
  it is why turbo is applied via reset rather than live, and it is the first suspect for
  anything timing-sensitive. If a change makes it worse, say so; CLS is at 88% and the design
  is close to its routing limit.
- Report the utilisation and timing after each build so `docs/UTILISATION.md` stays current.

## If clock_54m misses timing

Do not add multicycle constraints to the failing CPU paths. The worst one,
`cpu1/IORQ_n_i/Q -> wait_io_ff/CE`, is the wait-state generator's IDLE branch, which
samples IORQ on every `clk_54m` edge by design — it has to assert WAIT before the Z80
samples the bus. Relaxing it would produce a build that passes timing and corrupts
memory reads.

`fpga/sweep_pnr.tcl` (`gw_sh sweep_pnr.tcl` from `fpga/`) tries several place/route
effort combinations in one process, but as written it errors after the first trial —
each loop iteration re-sources `build_files.tcl`, and Gowin's `add_file` refuses a
file already in the project, so the second iteration fails with `unable to add file
"...", already in project`. It has not been fixed; running each combination as its
own `gw_sh` invocation (one process per trial, same pattern as `build.tcl`) works
around it and is what produced the results below.

**Sweep result (2026-08-21, from commit `0cf00b7`): none of the 6 combinations
close `clock_54m`.** `place_option 2 / route_option 2` — what `build.tcl` already
uses — ties for the best result. Route effort matters more than place effort:
dropping route effort alone costs ~1 MHz regardless of place effort, and dropping
both to 0 is far worse.

| place / route | Fmax | TNS (setup) | endpoints |
|---|---|---|---|
| 2 / 2 (current) | 53.217 MHz | -0.464 ns | 5 |
| 1 / 2 | 53.217 MHz | -0.464 ns | 5 |
| 0 / 2 | 49.941 MHz | -9.143 ns | 27 |
| 2 / 1 | 52.237 MHz | -2.220 ns | 14 |
| 1 / 1 | 52.237 MHz | -2.220 ns | 14 |
| 0 / 0 | 47.792 MHz | -22.206 ns | 33 |

PnR effort isn't the lever. The next step is trimming `swioports.vhd` while
preserving its `$40-$4F` readback exactly, and that is a decision to raise rather
than take.

## Current state

The core builds, boots, browses the SD card, runs games, reads the shield's DB9 joystick, and
renders the FPGA-Companion OSD on F12 with working reset, turbo, volume, scanlines, aspect,
stereo and second-SCC settings.

**Settings do not persist.** The menu's Save writes `msxnano.ini` through the companion's
FatFS, which reaches the card via the FPGA's SD target — and `mcu_sdc_din` is tied to zero
here, so the companion cannot see the SD card. Implementing that target is the outstanding
Phase 1 item.

Full status is in [README.md](README.md), the roadmap in [docs/ROADMAP.md](docs/ROADMAP.md),
and everything established about the hardware, the shield, the companion protocol and
upstream's quirks in [docs/FINDINGS.md](docs/FINDINGS.md) — **read that before re-deriving
anything**.

## Conventions

- **Update the docs in the same commit as the code.** The README's status table and the plan
  items are meant to describe the tree as it actually is. Stale docs have caused real errors
  here, including a BOM that pointed at pins now used by the joystick.
- **No emoji or status icons** in the docs. Plain words.
- Say plainly what is unverified. Verified-by-inspection is not verified-on-hardware, and the
  difference has mattered repeatedly on this project.
