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
