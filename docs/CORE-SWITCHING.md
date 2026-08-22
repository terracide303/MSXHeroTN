# Core switching on the Tang Nano 20K + MiSTeryShield20k

Loading a different FPGA core from the SD card, chosen from the `F12` overlay, without a PC.

**Status: researched, not started.** Everything below is established fact or a stated unknown;
no code has been written. The hardware facts were traced from the shield's PCB, Gowin's
configuration guide and FPGA-Companion's source, not assumed.

---

## Why this is not already done

Worth answering first, because MiSTle *does* have core switching — just not on this board.

**Their implementation writes SRAM, not flash.** `gowin_upload_core()` in FPGA-Companion issues
`GOWIN_COMMAND_ERASE_SRAM` and `XFER_WRITE` over JTAG. SRAM configuration is volatile, so a
broken or wrong core is undone by a power cycle. The risk is zero, which is what makes it
shippable.

**That route needs JTAG from the MCU, and this shield has none.** The complete net list of
`MiSTeryShield20kRPiPicoUSB` contains no TCK, TMS, TDI or TDO. FPGA-Companion's `MSP20K` target
("MiSTeryShieldPicoTN20k", `MISTLE_BOARD=5`) defines JTAG on GP12–GP15 and compiles in
`jtag.c`/`gowin.c`, but on this board those pins go nowhere. The builds that actually use it —
`DEV20K`, `DEV25K`, and the BL616 Console60k/Mega60k — are boards wired for it.

**And the fallback that makes flash-writing safe does not exist on this chip.** Gowin's UG290
lists *"AUTO BOOT Configuration Mode (Supported by LittleBee Family Only)"* and *"DUAL BOOT
Configuration Mode (Supported by LittleBee Family Only)"*, both reading from **internal** flash.
GW2A and GW2AR are **Arora** family with no internal flash. There is no golden image, no second
boot address, no automatic fallback: **whatever is at external flash address 0 is what boots.**

So the barrier is not effort. It is that the safe mechanism is unavailable here, and the
available mechanism is irreversible.

---

## What the hardware can do

All verified:

| | |
|---|---|
| The core writes its own boot flash | `build.tcl` sets `-use_mspi_as_gpio 1`; `flash_rw.v` does sector erase and page program. This is how settings persist at `0x280000` today |
| The core reads and writes the SD card | `sd_reader.sv`, including CMD24 writes |
| The boot menu parses FAT and lists files | the browser does this already |
| Reconfiguration can be triggered | `RECONFIG_N`, low pulse ≥25 ns, is wired from the Pico (`RECONFGN` in the net list) |
| A bitstream is about 900 KB on flash | the core flash erase spans `0x000000`–`0x0E0000`. The 7 MB `.fs` file is ASCII, roughly 8× its binary |

Note what this means: **the Pico never touches flash, the SD card, or JTAG.** Its entire role is
to pulse one pin. Even that has a zero-firmware fallback — tell the user to power cycle.

---

## The design

Two hops, because the thing being replaced cannot replace itself mid-write.

1. In MSXHeroTN, `F12` → **Core switching**. The core reads a small `loader.bin` from SD,
   writes it to flash address 0, and triggers reconfiguration.
2. The **loader** comes up: a minimal design that lists `.bin` files from the card, writes the
   chosen one to address 0, and triggers reconfiguration again.
3. The chosen core runs.

The loader lives **on the SD card**, not permanently in flash, so it costs no flash space and is
updated by copying a file.

### What each core needs

**To be loaded: nothing.** Any stock bitstream works unmodified.

**To be left: the switcher.** Once a core is at address 0, only that core can replace it —
`RECONFIG_N` just reboots address 0. A stock third-party core is therefore a one-way trip,
recoverable only by reflashing over USB-C.

For cores maintained in-house that is a small, identical addition: read a fixed file, write
flash, ask for reconfiguration. It does not need a browser or a UI.

---

## What has to be built

Roughly in order, each independently testable.

1. **Bulk flash write.** `flash_rw.v` writes six bytes today. It needs to stream ~900 KB:
   64 KB block erase (`CMD_BLOCK_ERASE`, already defined) rather than 4 KB sectors, and a
   continuous page-program loop. Estimate 2–15 s depending on erase granularity.
2. **A path from SD to flash.** The Z80 menu already finds the file; the simplest first version
   streams bytes through a new I/O port into the flash writer, rather than adding FAT parsing
   to the RTL.
3. **Verification before reconfiguring.** Read the written region back and compare. This is the
   difference between a failed switch and a board that needs a PC. Non-optional.
4. **The reconfiguration trigger.** v1: print "power cycle now". v2: a sysctrl command so the
   core can ask the Pico to pulse `RECONFGN`. Note the `PIN_nCFG` definition exists in
   FPGA-Companion only for `MISTLE_BOARD` 4 and 6, so board 5 would need it adding.
5. **The loader core.** A minimal design: SD reader, flash writer, a list on screen. No CPU
   needed if the UI is simple enough.
6. **A flash map convention.** Cores own regions beyond the bitstream — MSXHeroTN keeps its BIOS
   pack at `0x200000` and settings at `0x280000`. A bitstream ends well before `0x200000`, so
   switching preserves them, but two cores wanting the same region would collide silently.

---

## Risks

**Bricking is the real one.** A power cut during the write to address 0 leaves nothing bootable,
and recovery means USB-C and `openFPGALoader` — with the Tang out of the shield. The window is
seconds, and verification (step 3) does not shorten it.

Mitigations worth considering: keep the write as short as possible; refuse to start below some
condition; and document the recovery procedure *before* shipping the feature rather than after.

**A wrong file** — an `.fs` instead of a `.bin`, or a core for another device — bricks it just
as effectively. Validate the bitstream header before erasing anything.

---

## Open questions

- Can a design drive `RECONFIG_N` itself on this board? It is a dedicated configuration pin and
  on this shield it routes to the Pico, not to an FPGA IO — so probably not, but worth
  confirming before assuming the Pico is required.
- What is the flash chip's size and erase granularity? That sets the write time and whether
  several cores could be cached rather than fetched from SD each time.
- Does `openFPGALoader`'s raw `.bin` match what the FPGA expects at address 0 byte for byte, or
  is there a header transformation? `gowin.c` parses an `.fs` header; the flash image may differ.
