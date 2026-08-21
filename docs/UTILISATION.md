# Utilisation (Gowin place & route, GW2AR-18C QFN88)

Built from commit `8e6a5e9` on the Windows/Gowin machine (Gowin EDA 1.9.11.03,
`build.tcl`, `set_option -place_option 2 -route_option 2`).

## Resource usage

| Resource | Usage | Utilization |
|---|---|---|
| Logic (LUT/ALU/ROM16) | 14488/20736 (12011 LUT, 2075 ALU) | 70% |
| Register | 7425/15915 | 47% |
| CLS | 8977/10368 | 87% |
| I/O Port | 43/66 | 66% |
| IOLOGIC | 6/121 | 5% |
| BSRAM | 15/46 | 33% |
| DSP | 2.5/24 | 11% |

CLS is still the tightest resource at 87%, which is why `build.tcl` keeps
place/route effort at level 2.

## Max frequency summary

| Clock | Constraint | Actual Fmax | Logic level | Status |
|---|---|---|---|---|
| clock_audio | 3.600 MHz | 415.895 MHz | - | pass |
| clock_27m | 27.000 MHz | 70.613 MHz | - | pass |
| clock_54m | 54.000 MHz | 54.138 MHz | - | pass (thin) |
| clock_108m | 108.000 MHz | 184.178 MHz | - | pass |
| clock_108i | 108.000 MHz | 184.178 MHz | - | pass |
| fpga_companion_inst/mcu/n4_24 | 100.000 MHz | 220.554 MHz | - | pass |

All clocks pass, zero negative slack anywhere. **`clock_54m`'s margin dropped sharply**
— 57.049 MHz (previous build) to 54.138 MHz (this one), about 0.25% headroom — despite
this build containing *less* logic (14488 vs 14695 total), not more. Worth watching:
margin on this domain has not tracked logic size predictably build-to-build, so if a
future change regresses it again, don't assume the same congestion story that explained
the earlier `28c916d`/`0cf00b7` failures without checking.

## OSD-reset-wiring removal (commit `8e6a5e9`, currently flashable) — the current build

The previous build (`b903b2f`, below) closed timing (57.049 MHz) but **showed no
picture at all** on hardware — worse than the boot loop before it. Root cause per
`69791f9`: routing the OSD reset through a monostable stopped the immediate
self-clearing loop, but `fpga_companion`'s own init action sets `R=1` after every
reset, so the one-shot retriggered indefinitely and the machine never got past reset.
Fix: remove the OSD reset wiring entirely. Reset and Cold Boot are gone from the OSD
menu; Turbo no longer applies via reset (takes effect on next power cycle). **Do not
re-add OSD-driven reset wiring** without giving sysctrl its own power-on reset outside
the core reset domain — both prior attempts (level, and monostable) broke the machine
in different ways, and that's a design decision, not a build-side fix.

Menu XML and its generated `.hex` changed to match (two menu items dropped);
`msxnano_xml` extracted into RAM cleanly, no missing-file warnings.

## Reset-loop fix (commit `b903b2f`, superseded by `8e6a5e9` above)

The previous build (`ca77609`, below) closed timing but **did not boot**: the user
reported it flashed and showed the MSX screen briefly before resetting, over and over,
every time. Root cause per `6bf45e1`: the OSD reset wiring from `1911c67` had
`system_reset` (which lives in sysctrl, inside `fpga_companion`) drive `bus_reset_n` —
which resets `fpga_companion` itself. Asserting reset cleared the register asserting it,
releasing reset, re-entering the loop; the companion's own startup (`R=1` on init,
`R=0` on ready) hit this on every boot, not intermittently. Fixed by routing the OSD
reset through the same fixed-length monostable pulse pattern already used for
`config_reset`, so sysctrl clearing itself mid-pulse no longer shortens it.

This is a functional fix, not a timing one — `clock_54m` remains closed at 57.049 MHz
(up slightly from 55.626 MHz), CLS essentially unchanged (87%). The `cpu_din` mux tree
that actually closed timing (below) is untouched by this commit.

## clock_54m closes again (commit `ca77609`, superseded by `b903b2f` above)

`clock_54m` had closed once before (`fb6bea0`, 58.929 MHz — see below), then missed
across two more builds and a place/route sweep and a synthesis-option sweep that turned
out not to test anything (both documented below). The fix that actually worked:
`12444a6` (`e48a96f`) restructured the CPU read mux (`cpu_din` — the endpoint of two of
the failing paths) from a single 29-level priority chain into a tree: five contiguous
groups resolved in parallel, then resolved against each other, 11 levels deep instead of
26. Priority is preserved exactly by construction and was verified against the original
chain across 400,000 combinations of condition truth values, zero mismatches.

Fmax was 55.626 MHz against the 54.000 MHz constraint — a real pass, not a near-miss.
CLS eased from 88% to 87%. This bitstream closed timing but didn't boot (reset loop,
fixed in `b903b2f` above, which is the current `compiled/` build); the two failed
timing attempts below stay in `compiled/failed/` for reference.

## Original closure (commit `fb6bea0`, since regressed and now fixed above)

All clocks passed, including `clock_54m`, which failed its 54.000 MHz constraint in
the build before this one (53.798 MHz actual). Commit `2c35769` moved the F11 turbo-toggle
edge detection out of the `clk_54m` domain — the one domain that was missing timing —
and that alone appeared to close it (58.929 MHz actual, well over 54 MHz). It later
regressed (see below) until the `cpu_din` tree restructure above fixed it for good.

## Later attempt that regressed (not flashed)

A build from commit `28c916d` (OSD centring offsets, OSD-driven settings wiring, signed
volume fix) missed `clock_54m` again — Fmax 50.425 MHz, TNS -3.452 ns across 13
endpoints, all on CPU-to-memory-controller paths (`cpu1/RD` -> `mem1/sdram_addr`/
`sdram_seq`, `cpu1/u0/IStatus` -> `cpu_din`). CLS crept from 9048/10368 to 9124/10368
and registers from 7525 to 7535, which is the likely cause given CLS is already the
tightest resource at 88%. That bitstream is kept at
`compiled/failed/msxnano-mistle_tangnano20k_28c916d.fs` for reference, not flashed.
(Since fixed — see "clock_54m closes again" near the top of this document.)

## Second attempt: WiFi compiled out (still not flashed)

Commit `70de6ae` disabled `` `ENABLE_WIFI`` in `top.v` specifically to relieve the CLS
pressure behind the regression above, reasoning that `clock_54m` had closed before
(`fb6bea0`, 58.929 MHz) and missed twice since (`5da94ae` at 53.798 MHz, `28c916d` at
50.425 MHz) without those changes ever touching the failing cpu1/mem1 paths directly —
so giving the placer cells back was the fix aimed at the cause. It also left two
`Z80_goauld.sdc` constraints pointing at the now-gone `uwifi` instance, which broke
PnR outright (`TA2003: Can't set timing constraint to object`); commit `0cf00b7`
comments those out.

Built from `0cf00b7`, `clock_54m` improved a lot but still misses: Fmax 53.217 MHz
(vs 54.000 MHz), TNS -0.464 ns across 5 endpoints (down from -3.452 ns / 13). CLS only
eased slightly, 9124/10368 -> 9100/10368 (still 88%) — less than the WiFi-removal
commit expected, so that change alone isn't sufficient to close this domain. All other
clocks pass comfortably. Kept at
`compiled/failed/msxnano-mistle_tangnano20k_0cf00b7.fs`, not flashed. The table above
still reflects the current flashable build (`fb6bea0`).

## Place/route effort sweep (still on `0cf00b7`, still not flashed)

Commit `21745b7` added `fpga/sweep_pnr.tcl` to try several place/route effort
combinations, on the theory that PnR is deterministic and only an option change
moves the placer. The script itself errors after its first iteration (Gowin's
`add_file` rejects a file already in the project when `build_files.tcl` is
re-sourced on the second loop pass) — worked around by running each combination as
its own `gw_sh` process instead. See `CLAUDE.md` for the fix note.

None of the 6 combinations close `clock_54m`. `place_option 2 / route_option 2` —
what `build.tcl` already uses — ties for the best result (with `place_option 1`, same
numbers exactly). Route effort matters more than place effort: dropping it alone
costs about 1 MHz regardless of place effort, and dropping both to 0 is far worse.

| place / route | Fmax | TNS (setup) | endpoints | CLS |
|---|---|---|---|---|
| 2 / 2 (current) | 53.217 MHz | -0.464 ns | 5 | 88% |
| 1 / 2 | 53.217 MHz | -0.464 ns | 5 | 88% |
| 0 / 2 | 49.941 MHz | -9.143 ns | 27 | 89% |
| 2 / 1 | 52.237 MHz | -2.220 ns | 14 | 88% |
| 1 / 1 | 52.237 MHz | -2.220 ns | 14 | 88% |
| 0 / 0 | 47.792 MHz | -22.206 ns | 33 | 89% |

PnR effort isn't the lever here — nothing beats current settings. `CLAUDE.md` at the
time raised trimming `swioports.vhd` as a possible next step, then withdrew it after
tracing what it feeds (see below) — the fix that actually worked was the `cpu_din`
tree restructure documented near the top of this file. No new bitstream came out of
this sweep.

## Synthesis-option sweep (`iob`/`retime`) — inconclusive, not a real test

Commit `c82e239` shortened the `cpu_din` read mux (29 levels -> 26) and extended
`sweep_pnr.tcl` to sweep synthesis options — `-oreg_in_iob`/`-ireg_in_iob` (IO register
packing) and `-retiming 1` — since the place/route sweep above showed effort wasn't the
lever. Ran all four trials (`base`/`iob`/`retime`/`both`) as separate `gw_sh` processes,
2026-08-21, from commit `0cf00b7` plus the `cpu_din` shortening.

**All four produced a byte-identical netlist and PnR result**: CLS 8973/10368 (87%),
`clock_54m` Fmax 53.881 MHz against 54.000 MHz (closer than any prior attempt, thanks to
the `cpu_din` change alone — but still short). Checking each trial's recorded synthesis
project (`impl/gwsynthesis/sweep_<tag>.prj`, `<OptionList>` section) shows
`oreg_in_iob`/`ireg_in_iob`/`retiming` never appear — `set_option` silently dropped them
rather than applying them. Cross-checked against Gowin's own `SUG550-2.0.1E
GowinSynthesis User Guide`: it documents no such `set_option` flags for this synthesis
engine at all. `gw_sh` gives no warning when an unrecognized option is passed, so all
four trials completing cleanly with no errors is not evidence the options worked — it's
evidence they were no-ops. The `iob`/`retime` experiment was never actually run; see
`CLAUDE.md` for what a real version of it would need (a documented synthesis attribute
constraint or GSC file, not a `set_option` flag). No new bitstream from this sweep.
