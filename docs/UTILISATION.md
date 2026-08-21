# Utilisation (Gowin place & route, GW2AR-18C QFN88)

Built from commit `6389ac0` on the Windows/Gowin machine (Gowin EDA 1.9.11.03,
`build.tcl`, `set_option -place_option 2 -route_option 2`).

## Resource usage

| Resource | Usage | Utilization |
|---|---|---|
| Logic (LUT/ALU/ROM16) | 14091/20736 (12016 LUT, 2075 ALU) | 68% |
| Register | 7427/15915 | 47% |
| CLS | 9054/10368 | 88% |
| I/O Port | 43/66 | 66% |
| IOLOGIC | 6/121 | 5% |
| BSRAM | 15/46 | 33% |
| DSP | 2.5/24 | 11% |

CLS ticked back up to 88% (from 87%), still the tightest resource, why
`build.tcl` keeps place/route effort at level 2.

## Max frequency summary

| Clock | Constraint | Actual Fmax | Logic level | Status |
|---|---|---|---|---|
| clock_audio | 3.600 MHz | 492.285 MHz | - | pass |
| clock_27m | 27.000 MHz | 67.703 MHz | - | pass |
| clock_54m | 54.000 MHz | 56.973 MHz | - | pass |
| clock_108m | 108.000 MHz | 141.901 MHz | - | pass |
| clock_108i | 108.000 MHz | 141.901 MHz | - | pass |
| fpga_companion_inst/mcu/n4_24 | 100.000 MHz | 284.338 MHz | - | pass |

All clocks pass, zero negative slack anywhere. **`clock_54m` margin recovered** —
54.138 MHz (previous build) to 56.973 MHz (this one). Five commits landed together
this round (OSD reset fixed properly, OSD centring corrected, menu translated and
renamed to MSXHero), so no single change is isolated as the reason; nothing here
looks fragile.

## Settings persistence attempt: clock_54m misses despite a passing-looking Fmax (not flashed)

A build from commit `0b3f629` (first compile of `db4ac25` — settings persistence to
flash, plus wiring up previously-unused `system_turbo_boot`/`system_autofire`) misses
`clock_54m`: **the Max Frequency Summary shows 54.367 MHz, which looks like a pass, but
the Total Negative Slack Summary shows -0.555 ns across 6 Setup endpoints on `clock_54m`.**
These two reports can disagree — the Fmax number reflects one representative critical
path, not every endpoint's own setup check — so always check the TNS table, not just
whether Fmax clears the constraint number. All 6 failing endpoints are the familiar
`cpu1/u0/IStatus_0_s15/DO[8]` -> `cpu_din_*_s0/D` path family (worst -0.194 ns), the
same one behind every prior `clock_54m` miss here. CLS grew slightly (9054/10368 ->
9102/10368, 87% -> 88%), consistent with the new logic. No compile errors or warnings
on the two things the design side flagged as worth watching (`config_save_byte`,
the `af_limit` case statement) — this is a timing-margin problem, not a syntax one.
Kept at `compiled/failed/msxnano-mistle_tangnano20k_0b3f629.fs`, not flashed; the
table at the top of this document still reflects the current flashable build (`6389ac0`).

## Autofire rewrite attempt: clock_54m gets worse, not better (not flashed)

`aa52343` rewrote the OSD autofire rate from a 23-bit counter/comparator to a
comparator-free free-running counter, specifically to recover `clock_54m` from the
`0b3f629` miss above. CLS landed exactly where predicted — 9028/10368 (88%), below
the 9054 of the last good build — **but timing got markedly worse, not better.**

`clock_54m` Fmax 50.717 MHz against 54.000 MHz (flagged red in Gowin's own report
this time, not a look-alike pass), TNS -5.172 ns across 17 Setup endpoints — both
worse than `0b3f629`'s -0.555 ns / 6 endpoints. Failing paths now span two families:

- `cpu1/u0/IStatus_0_s15/DO[8]` -> `cpu_din_*_s0/D` (worst -0.524 ns), the recurring one
- `cpu1/RD_s0/Q` -> `mem1/sdram_addr_*_s0/D` / `mem1/sdram_seq_*_s*` (worst -0.599 ns),
  the class from the original `28c916d` regression, not present in `0b3f629`

All other clocks pass comfortably. CLS coming down while timing got worse means this
isn't simply a resource-count story — something about where the placer landed this
specific netlist hurt the CPU/memory-controller boundary despite there being more
room overall. Kept at `compiled/failed/msxnano-mistle_tangnano20k_aa52343.fs`, not
flashed; reported rather than trimmed further, per `CLAUDE.md`. The table at the top
of this document still reflects the current flashable build (`6389ac0`).

## Persistence-only attempt: clock_54m still fails, and this change doesn't touch it (not flashed)

`c2fcec4` reverted both autofire attempts back to byte-for-byte what shipped in
`6389ac0`; what remains is settings persistence, whose entire delta is 12 flip-flops
in `clk_27m`, one extra mux leg on `flash_write_din`, and two signal renames —
**nothing touches `clk_54m`**, per the commit's own accounting.

**`clock_54m` still fails.** Fmax 51.309 MHz against 54.000 MHz (a real fail, flagged
red), TNS -1.583 ns across 7 Setup endpoints. CLS is 9008/10368 (87%) — *lower* than
the last good build's 9054, and lower even than `aa52343`'s 9028, which also failed.
Failing paths:

- `cpu1/RD_s0/Q` -> `mem1/sdram_seq_1_s1/CE` / `sdram_seq_2_s1/CE` (worst -0.486 ns)
- `cpu1/RD_s0/Q` -> `state_wait_0_s4/CE` / `state_wait_1_s2/CE` (-0.196 ns)
- `cpu1/RD_s0/Q` -> `mem1/sdram_seq_0_s4/D`, `mem1/sdram_addr_17_s0/D` (-0.128, -0.061 ns)
- `cpu1/u0/IStatus_0_s15/DO[8]` -> `cpu_din_4_s0/D` (-0.032 ns)

**Worth surfacing plainly: CLS has now been lower than the last-passing build's in two
consecutive attempts (`aa52343` at 9028, this one at 9008), and both still fail
`clock_54m` — one of them with a change that touches nothing in the failing clock
domain at all.** Neither resource count nor "does the change touch clk_54m" predicts
the outcome here; something else is driving the placer's behaviour on this specific
netlist. All other clocks pass comfortably. Kept at
`compiled/failed/msxnano-mistle_tangnano20k_c2fcec4.fs`, not flashed; the table at
the top of this document still reflects the current flashable build (`6389ac0`).

## OSD reset done right, centring fixed, menu translated (commit `6389ac0`, currently flashable)

**Reset and Cold Boot work again, by fixing the actual cause instead of retrying
either broken approach** (`c52c1ac`). `fpga_companion` — which holds sysctrl, and
therefore the OSD's `system_reset` value — was reset from `~bus_reset_n`, the same
core reset the OSD's own reset drove into; that's why a level self-cleared (boot
loop, `ca77609`/`6bf45e1`) and a monostable retriggered forever (no picture,
`b903b2f`/`69791f9`). Fix: reset `fpga_companion` from `~clock_locked` (PLL lock)
instead, matching NanoMig's reference firmware, so sysctrl survives MSX resets and
`system_reset` can drive `bus_reset_n` directly. Side effect: an MSX reset no longer
resets the companion link or OSD state — correct for a peripheral, not a bug.

**OSD centring corrected** (`093bb4c`) — prior offsets were derived from HDMI encoder
porch timings, the wrong coordinate system; the OSD actually measures against the
VDP's own `hcnt`/`vcnt`. Recomputed from the VDP's real constants, fixing what the
user reported as ~8cm off-centre on a ~60cm picture. Vertical left alone (not
reported as off) but flagged as derived the same mistaken way, possibly needing the
same fix later.

**Menu translated to English and renamed to MSXHero v1.0** (`ac9e539`, `2bd2e32`) —
boot menu and OSD both now read "MSXHero", every user-facing string translated, WiFi
entry removed from the menu (compiled out on this fork, previously led to a dead
config screen). Both ROMs (boot menu and OSD `msxnano_xml`) extracted/loaded cleanly
in this build, no missing-file or size warnings.

## OSD-reset-wiring removal (commit `8e6a5e9`, superseded by `6389ac0` above)

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
