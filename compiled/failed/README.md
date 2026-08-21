# Failed builds

Bitstreams here built cleanly (synthesis + place & route completed, no errors) but
missed timing on `clock_54m` and are not flashed on hardware. Kept for reference in
case a future build needs to compare against what changed. The known-good, currently
flashable bitstream stays at `compiled/msxnano-mistle_tangnano20k.fs`.

## msxnano-mistle_tangnano20k_28c916d.fs

Built from commit `28c916d` (Gowin EDA 1.9.11.03, `fpga/build.tcl`, target
GW2AR-18C QFN88), 2026-08-21.

`clock_54m` Fmax 50.425 MHz against a 54.000 MHz constraint — Total Negative Slack
-3.452 ns across 13 endpoints, all within the `clock_54m` domain. Worse than any
previous build; the last working build (`fb6bea0`, currently in `compiled/`) passed
this same clock at 58.929 MHz.

Failing paths cluster in two groups, both at the CPU/memory-controller boundary:

- `cpu1/RD_s0/Q` -> `mem1/sdram_addr_*_s0/D` and `mem1/sdram_seq_*_s*` (worst -0.656 ns)
- `cpu1/u0/IStatus_0_s15/DO[8]` -> `cpu_din_*_s0/D` (worst -0.365 ns)

Nothing in this round's source diff (OSD centring offsets, OSD-driven settings wiring,
signed-volume fix) touches those paths directly. CLS usage grew slightly (9048/10368 ->
9124/10368) and registers (7525 -> 7535); CLS is already the tightest resource on this
device at 88%, so the likely cause is congestion pushing an already-marginal
CPU<->memory path over, rather than any single change being obviously at fault. See
`docs/UTILISATION.md` for the full resource/timing breakdown of this attempt.

Do not flash this one — it's kept only so a later build (once `clock_54m` is closed
again) has something to diff against.

## msxnano-mistle_tangnano20k_0cf00b7.fs

Built from commit `0cf00b7` (Gowin EDA 1.9.11.03, `fpga/build.tcl`, target
GW2AR-18C QFN88), 2026-08-21. Includes `3dddae4` ("compile out the unreachable
WiFi", intended specifically to relieve the CLS pressure behind the `28c916d`
failure above) plus a same-day fix (`0cf00b7`) commenting out two `set_false_path`
lines in `Z80_goauld.sdc` that referenced `uwifi/*` pins no longer present once
`` `ENABLE_WIFI`` was disabled — without that fix PnR errors out
(`TA2003: Can't set timing constraint to object`) and never produces a bitstream.

Much closer than the `28c916d` attempt, but still fails: `clock_54m` Fmax
53.217 MHz against 54.000 MHz — TNS -0.464 ns across only 5 endpoints (down from
-3.452 ns / 13 endpoints). Worst offenders, same CPU/memory-controller boundary
as before:

- `cpu1/IORQ_n_i_s0/Q` -> `wait_io_ff_s2/CE` (-0.136 ns)
- `cpu1/u0/IStatus_0_s15/DO[8]` -> `cpu_din_0_s0/D` (-0.119 ns)
- `cpu1/u0/IStatus_0_s15/DO[8]` -> `mem1/sdram_addr_7_s0/D` (-0.110 ns)

CLS only dropped slightly (9124/10368 -> 9100/10368, still 88%) — less relief than
the commit's reasoning expected, so WiFi removal alone isn't quite enough to close
this domain. All other clocks pass comfortably. Do not flash; kept for comparison.
