# Notes from the Windows build machine, for the Mac instance

Read this alongside `docs/UTILISATION.md` (full resource/timing report) and the
top-level `CLAUDE.md` (build instructions for this machine).

## Current bitstream

`msxnano-mistle_tangnano20k.fs` in this folder is built from commit `ca77609`
(Gowin EDA 1.9.11.03, `fpga/build.tcl`, target GW2AR-18C QFN88). Synthesis and
place & route both completed with no errors.

**`clock_54m` timing closes again, for the first time since `fb6bea0`.** Fmax
55.626 MHz against the 54.000 MHz constraint, zero negative slack anywhere,
all six clock domains pass. The fix is `12444a6` (`e48a96f`), which
restructured the CPU read mux (`cpu_din`) from a single 29-level priority
chain into a five-group tree, 11 levels deep, verified equivalent to the
original priority ordering across 400,000 truth-table combinations. CLS also
eased to 8982/10368 (87%, down from 88%). Two earlier attempts to close this
same domain (`28c916d`, `0cf00b7`) failed and are archived at
`compiled/failed/` with `docs/UTILISATION.md` carrying the full history if
useful — this build supersedes both.

The commit itself flagged one build-time risk worth confirming landed clean:
the new mux's group wires forward-reference signals declared later in
`top.v` (`sd_busreq_w` at line 2754, `config_req` at line 2153) from
continuous assignments rather than the old procedural-block style. Gowin
accepted it without complaint — no errors, no new warnings beyond the usual
two long-standing ones (`PINFILTER`/`NL0002` module-swept-in-optimizing
messages, and the `TA1132` clock-not-created warning on
`fpga_companion_inst/mcu/n4_24`).

Priority logic in `cpu_din`'s mux was restructured but is claimed
behaviorally identical by the commit's own verification (not independently
re-verified here beyond a clean build) — worth keeping an eye on CPU read
correctness (memory reads, I/O port reads, ROM/RAM select) on hardware given
how central this mux is, even though nothing in the build log suggests a
problem.

## Flashing

This machine cannot flash the board — the Tang Nano 20k's onboard Sipeed debug
chip (`VID_349B:PID_6160`) isn't a genuine Gowin cable, and Windows keeps
binding it as a plain serial port rather than exposing a JTAG-capable USB
interface, so neither Gowin's own Programmer nor `openFPGALoader` can open it
from here. Flashing stays on the Mac side with `openFPGALoader`, as before.
