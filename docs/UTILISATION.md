# Utilisation (Gowin place & route, GW2AR-18C QFN88)

Built from commit `5da94ae` on the Windows/Gowin machine (Gowin EDA 1.9.11.03,
`build.tcl`, `set_option -place_option 2 -route_option 2`).

## Resource usage

| Resource | Usage | Utilization |
|---|---|---|
| Logic (LUT/ALU/ROM16) | 14692/20736 (12220 LUT, 2070 ALU) | 71% |
| Register | 7525/15915 | 48% |
| CLS | 9081/10368 | 88% |
| I/O Port | 43/66 | 66% |
| IOLOGIC | 6/121 | 5% |
| BSRAM | 17/46 | 37% |
| DSP | 2.5/24 | 11% |

CLS at 88% is the tightest resource — routing congestion there is why `build.tcl`
already raises place/route effort to level 2.

## Max frequency summary

| Clock | Constraint | Actual Fmax | Logic level | Status |
|---|---|---|---|---|
| clock_audio | 3.600 MHz | 431.481 MHz | 3 | pass |
| clock_27m | 27.000 MHz | 73.223 MHz | 14 | pass |
| clock_54m | 54.000 MHz | 53.798 MHz | 9 | **fail — misses constraint by ~0.2 MHz** |
| clock_108m | 108.000 MHz | 152.675 MHz | 4 | pass |
| clock_108i | 108.000 MHz | 152.675 MHz | 4 | pass |
| fpga_companion_inst/mcu/n4_24 | 100.000 MHz | 126.069 MHz | 2 | pass |

`clock_54m` is the one real timing violation in this build — it is the same net
(`ex_clk_27m_d`/pixel-clock domain) already flagged in `build.tcl`'s comment about
routing congestion (~91% CLS at the time that comment was written; now 88%). Worth
watching if further logic is added to that domain — it may need more PnR effort, a
constraint relaxation, or logic reduction to close.
