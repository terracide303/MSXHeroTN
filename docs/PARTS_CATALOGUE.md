# Parts catalogue — check here before writing anything

**`FPGA_WORKFLOW.md` rule minus-three says search before you write. This is the
index that makes that rule actionable instead of advice.**

Every path below was verified to exist on 2026-08-30. Line counts are real.

**Search order: this page, then the upstream author's other cores, then GitHub —
and your own projects LAST.** Your own shelf gets found by accident anyway, and
it is the one whose assumptions slip past unread. `memory_ctrl.v` was reuse from
our own MSX core, proven on the same board, and it cost four bugs and a week
because it was built for a different machine.

---

## Memory

| Part | Where | Lines | Licence | Verdict |
|---|---|---|---|---|
| **`sdram.sv`** | `PCEHeroTN/source/nanomig/` | 499 | **GPLv3** | **USE THIS.** From MiSTle-Dev/NanoMig; its header says *"for the MiSTer SDRAM, the TN20k etc"*. Two independent ports, one `sync` pulse, explicit refresh, `ack` per port, optional 64-bit reads |
| `memory_ctrl.v` | `PCEHeroTN/source/msxherotn/` | 463 | ours | **AVOID for new cores.** Built for a Z80 and a V9958: assumes a 1:5 clock ratio, inherits refresh from a CPU signal that may not exist, and keys on video phase corners the software can change at runtime |
| `sdram_test_top.v` | `MSXZero/fpga/bringup/` | 164 | ours | an earlier bring-up test |
| **`pcehero_sdtest_top.v`** | `PCEHeroTN/rtl/` | 503 | ours | **the better one.** Address-derived pattern, loops forever, read-only after pass 1, count reported as a number. Copied into `template/rtl/sdtest_top.v` |

**Two things learned the hard way and easy to miss:**

- **Clock the chip from a phase-shifted output.** Gowin rPLL `CLKOUTP` with
  `PSDA_SEL = "1100"` (270°). Unshifted, the chip samples on the same edge the
  FPGA switches on — it works nearly always, and "nearly" is one bad word in
  millions.
- **The first read after a long write burst is unreliable** — bus turnaround.
  Measured on hardware, deterministic, exactly one read. Issue a throwaway read
  after any bulk write before anything you trust depends on it.

---

## Getting text out

| Part | Where | Lines | Verdict |
|---|---|---|---|
| **`uart_tx.v`** | `MSXnano-MiSTle/fpga/src/` | 91 | 8N1, parameterised clock and baud. Already wired to **pin 69** in that project and switched off for area. Copied into `template/rtl/` |
| `uart*.vhd` | `NextHeroTN/source/serial/` | — | VHDL alternative, RX and TX |

**Tang Nano 20K pins: TX = 69, RX = 70**, through the USB-C port to the on-board
BL616. **These are not in the vendor datasheet** — they are named in
`MiSTle-Dev/bl616debugdisplay`'s `.cst` and in MSXHeroTN's own `tang9k.cst`. A
whole debug channel was abandoned once on the strength of the datasheet's
silence.

Normal mode presents **two** `/dev/cu.usbserial-*` ports: one JTAG, one a plain
UART. One `/dev/cu.usbmodem*` instead means the BL616 is in its ROM bootloader.

---

## Flash

| Part | Where | Lines | Verdict |
|---|---|---|---|
| `flash_reader.v` | `PCEHeroTN/rtl/` | 211 | read-only streamer, one `0x03` command then bytes out, ~2.7 MB/s. Right for loading a ROM at boot |
| `flash_rw.v` | `CoreSwitch/rtl/vendor/` | 492 | read **and write**. Right when the core must persist something |

Reaching the boot flash needs `set_option -use_mspi_as_gpio 1`.

---

## Video

| Part | Where | Verdict |
|---|---|---|
| `source/hdmi/*.sv` (10 files) | `PCEHeroTN/` | hdl-util/hdmi. TMDS encoding, proven on this board. Needs `-verilog_std sysv2017` |
| `pce_video.v` | `PCEHeroTN/rtl/` | ping-pong line buffer, doubles 15.7 kHz to 31.5 kHz for 720×480p60. Retarget-able to any 15 kHz core |
| `hdmi_test_top.sv` | `MSXZero/fpga/bringup/` | colour-bar test pattern. **Build this first on a new board** |

---

## Clocks

| Part | Where | Verdict |
|---|---|---|
| **`clocks.v`** | `PCEHeroTN/rtl/` | the Gowin pattern: one rPLL to the fast clock, a `CLKDIV` for the system clock, a second rPLL for the HDMI serialiser, **and `CLKOUTP` shifted 270° for the SDRAM chip**. Copied into `template/rtl/` |

`CLKDIV` off the PLL is preferred over asking one PLL for both clocks — it keeps
the two phase-locked, so their crossings are real paths rather than pessimistic
CDC, provided the `.sdc` declares the relationship.

---

## Host / companion — keyboard, gamepads, OSD, SD

All from FPGA-Companion (**Apache-2.0**), already integrated in MSXHeroTN.

| Part | Where | Lines |
|---|---|---|
| `fpga_companion.v` | `MSXnano-MiSTle/fpga/src/usb/` | 178 |
| `mcu_spi_new.v` | `MSXnano-MiSTle/fpga/src/usb/` | 124 |
| `sys_ctrl.v` | `MSXnano-MiSTle/fpga/src/usb/` | 315 |
| `osd_u8g2.v` | `MSXnano-MiSTle/fpga/src/usb/` | 175 |

**SD card, HID and flash blocks** live in `MiSTle-Dev/bl616debugdisplay` under
`src/misc/` — `sd_card.v`, `sd_rw.v`, `sdcmd_ctrl.v`, `hid.v`, `mcu_spi.v`,
`sysctrl.v`, `flash_dspi.v`. Not cloned locally; fetch when needed.

**Board caveat:** Tang Nano 20K boards from ~2024 (`3921`, `3923`) often will
not run companion firmware on the **on-board** BL616. The MiSTeryShield20k
sidesteps this with an **RP2040**. Budget for the external route.

---

## Where to look when this page does not have it

1. **`MiSTle-Dev/*`** — C64Nano, NanoMig, MiSTeryNano, VIC20Nano, NanoMac,
   A2600Nano, NanoApple2, C16Nano. All ship on Tang boards; all have solved the
   board-level problems already.
2. **The upstream author's other cores.** Torlus, nand2mario, harbaum,
   Jotego — a designer who solved it once has usually solved it three times.
3. **MiSTer / MiST** for the machine itself. Prefer the branch whose **ports
   match**, not the most accurate one.

---

## Adding to this page

When a phase finishes, anything reusable goes here **with its licence and with
what it is proven on**. "Proven on this chip" is worth much less than it sounds
if it was proven doing something else — say which.

And record what you decided **not** to reuse, and why. "Ours differs because X"
is a claim someone can check later; silence is not.
