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

`fpga/sweep_pnr.tcl` now takes a tag and runs **one trial per process** — the loop
version failed because Gowin's `add_file` refuses a file already in the project when
`build_files.tcl` is re-sourced. Run from `fpga/`:

```
gw_sh sweep_pnr.tcl <tag>
```

**Place/route effort has already been swept (2026-08-21, from `0cf00b7`) and none of
the six combinations closed.** `place_option 2 / route_option 2` — what `build.tcl`
already uses — was the best available, and place effort 1 and 2 gave byte-identical
results. Route effort matters more: dropping it alone costs about 1 MHz.

| place / route | Fmax | TNS (setup) | endpoints |
|---|---|---|---|
| 2 / 2 (current) | 53.217 MHz | -0.464 ns | 5 |
| 1 / 2 | 53.217 MHz | -0.464 ns | 5 |
| 2 / 1 | 52.237 MHz | -2.220 ns | 14 |
| 1 / 1 | 52.237 MHz | -2.220 ns | 14 |
| 0 / 2 | 49.941 MHz | -9.143 ns | 27 |
| 0 / 0 | 47.792 MHz | -22.206 ns | 33 |

**So PnR effort is not the lever, and there is no point sweeping it again.** What that
sweep never touched is the *synthesis* options, which attack the problem differently.
Those are the remaining free experiments:

```
gw_sh sweep_pnr.tcl iob      # -oreg_in_iob/-ireg_in_iob: pack registers next to
                             # pins into the IO blocks; frees CLS, shortens IO paths
gw_sh sweep_pnr.tcl retime   # -retiming 1: let synthesis move registers across
                             # logic to balance path delays
gw_sh sweep_pnr.tcl both
```

Report the `clock_54m` Fmax for each. If one closes, set those options in `build.tcl`,
build normally, and commit the bitstream.

**Do not trim `swioports.vhd`.** An earlier note here suggested it as the next step;
that was withdrawn after tracing what it feeds. Its `iSlt2_linear` and `Slot2Mode`
outputs drive the megaram mapper's `map_linear` and `map_sel`, so it is part of how
cartridges are mapped, not a dormant status block — and the likely saving is small
(removing 693 lines of WiFi freed only 24 CLS). Breaking it would show up as games
failing to load or loading corrupt.

If the synthesis sweep also fails, stop and report rather than cutting features. The
remaining options are a judgement call for the user: finish shortening the `cpu_din`
mux (26 levels now, ~8 possible, but it does not touch the worst path), cut a feature,
or stay on tag `known-good-fb6bea0` — the last build verified working on hardware,
with timing closed at 58.929 MHz.

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
