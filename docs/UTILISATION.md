# Utilisation (Gowin place & route, GW2AR-18C QFN88)

Built from commit `fb6bea0` on the Windows/Gowin machine (Gowin EDA 1.9.11.03,
`build.tcl`, `set_option -place_option 2 -route_option 2`).

## Resource usage

| Resource | Usage | Utilization |
|---|---|---|
| Logic (LUT/ALU/ROM16) | 14732/20736 (12260 LUT, 2070 ALU) | 72% |
| Register | 7525/15915 | 48% |
| CLS | 9048/10368 | 88% |
| I/O Port | 43/66 | 66% |
| IOLOGIC | 6/121 | 5% |
| BSRAM | 17/46 | 37% |
| DSP | 2.5/24 | 11% |

CLS at 88% is still the tightest resource — routing congestion there is why `build.tcl`
already raises place/route effort to level 2.

## Max frequency summary

| Clock | Constraint | Actual Fmax | Logic level | Status |
|---|---|---|---|---|
| clock_audio | 3.600 MHz | 388.670 MHz | 2 | pass |
| clock_27m | 27.000 MHz | 62.897 MHz | 15 | pass |
| clock_54m | 54.000 MHz | 58.929 MHz | 16 | pass |
| clock_108m | 108.000 MHz | 133.840 MHz | 3 | pass |
| clock_108i | 108.000 MHz | 133.840 MHz | 3 | pass |
| fpga_companion_inst/mcu/n4_24 | 100.000 MHz | 200.912 MHz | 2 | pass |

All clocks now pass, including `clock_54m`, which failed its 54.000 MHz constraint in
the previous build (53.798 MHz actual). Commit `2c35769` moved the F11 turbo-toggle
edge detection out of the `clk_54m` domain — the one domain that was missing timing —
and that alone appears to have closed it (58.929 MHz actual now, well over 54 MHz).
