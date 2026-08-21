# Notes for building this on the Windows/Linux machine

This repo is developed across two machines: a Mac (editing, flashing, research) and a PC
with **Gowin EDA**, which is the only place it can be synthesized — Gowin has no macOS build.
If you are the instance on the PC, this file is for you.

## Division of labour

This project runs across two machines and two Claude sessions. They cannot talk to each
other; the repository is the only channel, so the split is by **file ownership** and each
side stays out of the other's files.

**This machine (the PC) builds. It does not author the design.**

Owns, and may commit freely:

- `compiled/` — bitstreams, and `compiled/failed/` for ones that miss timing
- `compiled/BUILD_NOTES.md` — observations from the build
- `docs/UTILISATION.md` — resource and timing results

Does **not** edit:

- `fpga/` — RTL, constraints, `.sdc`, `.tcl`, the menu XML
- `README.md`, `docs/FINDINGS.md`, `docs/ROADMAP.md`, `docs/BOM.md`
- this file

**If a build is blocked by something in the source** — a missing file, a constraint
referring to a signal that no longer exists, a syntax error — the useful thing is usually
to fix it and keep going rather than stall for a round trip. That is fine, with two
conditions: keep the change as small as it can be, and say so **prominently** in the commit
subject, not buried in the body. `0cf00b7` is the right pattern: a one-line `.sdc` fix,
clearly named, because PnR could not otherwise produce a bitstream at all.

What not to do is fix a *design* problem — restructure logic, relax a constraint, disable a
feature to make timing close. Those are decisions with consequences the other side is
tracking. Report and stop instead; the reasoning behind several of them is already recorded
here and in `docs/FINDINGS.md` precisely so they are not re-litigated.

**Neither side is notified when the other pushes.** Both rely on the user to say when
something is ready, so make results easy to find: a clear commit subject and the numbers in
`docs/UTILISATION.md` rather than only in the session transcript.

## Build this next: the autofire rewrite on top of `db4ac25`

`0b3f629` compiled clean but missed `clock_54m` — TNS -0.555 ns over 6 endpoints, CLS
9054 -> 9102. Thank you for checking the TNS table rather than trusting the 54.367 MHz
Fmax; that distinction is now recorded in `docs/UTILISATION.md` and is worth applying to
every future build here.

The +48 CLS was almost entirely one block, and it was in `clk_54m`: the OSD autofire rate
had been built as a 23-bit counter plus a 23-bit limit register plus a variable
comparator. That has been replaced with a free-running counter whose square wave is
simply one of its bits — **no comparator at all**, which is cheaper than the fixed-rate
code that was there before this feature existed (it compared 22 bits against a constant
every cycle). The rates move from 5/10/20 Hz to 3/6/13 Hz as a result, which is why the
menu labels changed.

Expectation: CLS should land at or below the 9054 of the last good build, and `clock_54m`
should return to closing. If it still misses, say so and stop — do not start trimming;
the next step is the design side's call and the fallback is dropping the autofire rate
control entirely, keeping only persistence.

Everything else from the previous brief still applies:

## Previous brief: `db4ac25`

Settings persistence, plus two OSD entries that were connected to nothing. No new source
files, so `build_files.tcl` and the `.gprj` are unchanged — it is edits to `top.v`,
`sys_ctrl.v`, `fpga_companion.v` and the menu XML (with `msxnano_xml.hex` already
regenerated).

It has **never been compiled** — there is no Verilog toolchain on the Mac side, so this build
is the first thing that will parse it. Specifically worth reporting:

- **`clock_54m` and CLS.** The change is small (a 23-bit counter compare against a register
  instead of a constant, one 8-bit mux leg, a handful of flip-flops), but timing here is
  congestion-dominated and has swung several MHz on changes this size before.
- **Anything Gowin says about `config_save_byte`** — a continuous assignment placed just
  above `flash_write_din`, referencing `volume_ff`/`db9_port_ff`/`autofire_ff` which are
  declared near the top of the module.
- **The `af_limit` case statement**, which is a clocked `case` on a 2-bit select inside the
  existing autofire counter block in the `clk_54m` domain.

If it does not parse, the fix is almost certainly mechanical — say what the error was.

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
- **`clock_54m` closes, but only just** — 55.626 MHz against 54.000 as of `12444a6`. It
  missed for a run of builds before that (see below), and it is still the first suspect for
  anything timing-sensitive: CLS is at 87% and the design is close to its routing limit.
  If a change makes it worse, say so rather than working around it.
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

**So PnR effort is not the lever, and there is no point sweeping it again.**

**The `iob`/`retime` synthesis-option sweep is also a dead end — but not because the
options don't help. They don't exist.** `-oreg_in_iob`/`-ireg_in_iob`/`-retiming` are not
documented `set_option` flags for GowinSynthesis (checked against Gowin's own
`SUG550-2.0.1E GowinSynthesis User Guide`, which covers `set_option` usage and the full
synthesis-attribute-constraint list — no such flags appear anywhere in it). Confirmed by
running all four `base`/`iob`/`retime`/`both` trials (2026-08-21, from commit `0cf00b7`,
after the `cpu_din` mux shortening in `c82e239`): every trial produced a byte-identical
netlist and PnR result — same resource usage (CLS 8973/10368), same `clock_54m` Fmax
(53.881 MHz, still short of 54.000 MHz). The options were silently swallowed by
`set_option`, not applied; `gw_sh` gives no warning when that happens, so a clean run
looks identical to a real (failed) test. Do not read "no error" as "the flags worked."

If IO-register-packing or retiming behavior is wanted here, it would have to come through
GowinSynthesis's documented mechanism — per-signal/per-module attribute constraints
(`syn_preserve`, `syn_srlstyle`, etc., see the User Guide) or a GSC constraint file — not
a `set_option` flag on the whole build. Nobody has tried that; it is a different, unstarted
experiment, not a retry of this one.

**Do not trim `swioports.vhd`.** An earlier note here suggested it as the next step;
that was withdrawn after tracing what it feeds. Its `iSlt2_linear` and `Slot2Mode`
outputs drive the megaram mapper's `map_linear` and `map_sel`, so it is part of how
cartridges are mapped, not a dormant status block — and the likely saving is small
(removing 693 lines of WiFi freed only 24 CLS). Breaking it would show up as games
failing to load or loading corrupt.

**What has actually moved the needle is the `cpu_din` read mux.** It was a single
priority chain feeding the register at the end of two of the failing paths. Shortening
it 29 -> 26 levels in `c82e239` freed 127 CLS (9100 -> 8973) and took `clock_54m` from
53.217 to 53.881 MHz — about five times the relief that removing 693 lines of WiFi
bought, and most of the remaining gap.

`12444a6` goes further: the mux is now a **tree**, five groups resolving in parallel
and then against each other, **26 levels down to 11**. Priority is preserved by
construction (contiguous groups, original order within and between) and was verified
against the old form across 400,000 combinations of condition truth values, zero
mismatches. **This is the build to try next.**

One thing to watch: the new group wires reference signals declared later in `top.v`
(`sd_busreq_w` at 2754, `config_req` at 2153). The old chain did too, but from inside a
procedural `always` block rather than continuous assignments, and tools differ on how
strict they are. If Gowin objects it will be a compile error, not silent misbehaviour —
say so rather than working around it.

If that still misses, stop and report rather than cutting features; that is the user's
call. What remains is merging the nine `ram_dout` conditions into one test (~8 levels,
but only valid if those decodes are provably mutually exclusive — `megarom_req` sits
below `sd_busreq_w`/`sram_busreq_w` today, so merging flips which wins if they can
overlap), cutting a feature, or staying on tag `known-good-fb6bea0` — the last build
verified working on hardware, with timing closed at 58.929 MHz.

## Current state

`clock_54m` **closes** as of the `cpu_din` tree restructure (`12444a6`): 55.626 MHz against
54.000, zero negative slack on all six domains, CLS 87%. That ended a run of builds that
missed it; `docs/UTILISATION.md` records what was tried and what did not work, so it is not
repeated. Do not re-sweep place/route effort, and note that
`-oreg_in_iob`/`-ireg_in_iob`/`-retiming` do not exist in this synthesis engine.

The core builds, boots, browses the SD card, runs games, reads the shield's DB9 joystick, and
renders the FPGA-Companion OSD on F12 -- centred, named MSXHero, with turbo, volume,
scanlines, aspect, stereo, second-SCC, Reset and Cold Boot all verified working on hardware.
The boot menu is English, titled MSXHero TN 1.0.

Phase 1 is complete apart from persistence, which is written and awaiting its first build.

**Do not reset `fpga_companion` from `~bus_reset_n`.** It is reset from PLL lock
(`~clock_locked`) deliberately, because `sysctrl` lives inside it and holds the OSD's values —
including the reset the OSD drives. Wiring the companion to the core reset makes an OSD reset
impossible: as a level it boot-loops the machine, and through a one-shot it gives no picture
at all. Two builds were lost to this before checking that NanoMig uses `!pll_lock` for the
same thing. See `docs/FINDINGS.md`.

**Settings persistence is written but never built.** It goes into the FPGA flash, reusing the
six-byte block at `0x280000` the on-MSX `S` menu has always used -- byte 5 was written as
`0xFF` and never read, and now carries volume, DB9 port and autofire. A new sysctrl id `W`
triggers the write. The OSD's `<save file=".."/>` is deliberately NOT used: it goes through
the companion's FatFS, which needs an SD target the core does not implement.

**This build is the first test of it.** Watch for: CLS and `clock_54m` (the change is small,
but this design's timing is congestion-sensitive), and whether `config_save_byte` and the
`af_limit` case synthesize without complaint. Report numbers either way.

The same commit connects `system_turbo_boot` and `system_autofire`, which were wired to
sysctrl and read by nobody -- the OSD's Boot-in-turbo and Autofire entries did nothing.

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
