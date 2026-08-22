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

## The flash image — answered

A `.fs` file is **ASCII, one character per bit**: `//` comment lines, then data lines of `0`
and `1`. Our bitstream is 2110 lines of 3440 characters plus a few short ones — 907,418 bits.
The flash image is those bits packed 8 to a byte, MSB first, comments discarded. Nothing else
happens to it.

That gives **907,418 bytes, 886 KB**, which sits inside the `0x000000`–`0x0E0000` span
openFPGALoader erases with 10,086 bytes to spare — the difference being erase-block rounding.

`tools/coreswitch/fs2bin.py` does the conversion and is the tool that prepares cores for the
SD card. **Store cores packed, not as `.fs`:** eight times smaller to read, and the FPGA never
has to parse ASCII while rewriting its own boot flash.

### This also makes the wrong-file risk checkable

The packed image begins with 22 bytes of `0xFF`, then:

```
a5 c3 06 00 00 00 00 00 08 1b 10 00 ...
```

`A5 C3` is Gowin's bitstream preamble, and **`08 1B` is the GW2AR-18 IDCODE** — the same value
`gowin.h` defines as `IDCODE_GW2AR18`. Both sit at fixed offsets, readable before a single byte
is erased.

So the loader can refuse a file that is not a bitstream, or is a bitstream for a different
device, without taking any risk at all. That was listed above as an accepted danger; it is now
a validation step.

---

## Card layout

Cores live in their own folder, one directory each, with a manifest saying what goes where:

```
/CORES/
    NANOMIG/
        NANOMIG.BIN      the packed bitstream
        KICK13.ROM       whatever else that core needs in flash
        CORE.MAP         what to write, and to which address
    MSXHERO/
        MSXHERO.BIN
        GOAULD.BIN       the MSX BIOS pack
        CORE.MAP
```

`CORE.MAP` is deliberately trivial to parse from Z80 — a filename, whitespace, a hex address,
one per line:

```
# NanoMig
NANOMIG.BIN  000000
KICK13.ROM   200000
```

**This solves the flash-map problem.** Earlier this document warned that two cores wanting the
same flash region would collide silently. They still overlap — but now each core *declares* its
regions, so the loader knows the full set before it erases anything, can check they do not
overrun each other, and can report what it is about to do.

**And it makes returning symmetric.** MSXHeroTN becomes just another entry in `/CORES`, with its
own bitstream and its BIOS pack at `0x200000`. Switching to NanoMig overwrites that BIOS pack;
switching back rewrites it. The loader needs no special case for "home" — there isn't one.

Worth knowing the cost: a switch is then ~886 KB of bitstream plus whatever data the core
declares. For MSXHeroTN that is another 512 KB, so about 1.4 MB per switch.

### Keeping /CORES out of the file browser

It has no business in a list of games. Two ways, and the first already works:

**Set the DOS hidden attribute on the folder.** As of 1.1 the browser skips entries marked
hidden or system, so it disappears immediately, while staying visible on a Mac or PC. Zero code.

**Or match the name.** More robust, since it does not depend on whoever prepared the card
remembering to set an attribute — a literal check for a top-level directory named `CORES` in
the scan is a handful of Z80 instructions. Worth doing if this feature ships properly.

---

## Staged plan

Each stage is independently testable, and the risky one is deliberately last.

**Stage 0 — the converter.** Done: `tools/coreswitch/fs2bin.py`, verified against the shipping
bitstream.

**Stage 1 — read a core from SD and verify it, writing nothing.** Find `core.bin` in the
browser, stream it, check the magic and IDCODE, checksum it, report. No erase, no flash, no
risk. Proves the read path and the validation end to end.

**Stage 2 — bulk flash write, to a safe address.** `flash_rw.v` writes six bytes today; it needs
64 KB block erase (`CMD_BLOCK_ERASE`, already defined) and a continuous page-program loop.
Test it against an *unused* region — never address 0 — then read back and compare. Measures the
real write time and proves the writer before it can do damage.

**Stage 3 — the reconfiguration trigger.** Simplest first: write nothing, just confirm that
power-cycling picks up whatever is at address 0. Then, optionally, a sysctrl command so the core
can ask the Pico to pulse `RECONFIG_N`. Note `PIN_nCFG` is defined in FPGA-Companion only for
`MISTLE_BOARD` 4 and 6, so board 5 needs it adding.

**Stage 4 — write address 0 for real.** Only after 1–3 pass. Validate, erase, write, **read back
and compare**, and only then reconfigure. If the comparison fails, say so and do not reboot —
the old core is gone either way, but the user learns it from a message rather than a black
screen.

**Stage 5 — the loader core.** A minimal design: SD reader, flash writer, a list on screen.
Only worth building once 1–4 work, because it is the same machinery with a smaller UI.

---

## Still unknown

- Can a design drive `RECONFIG_N` itself on this board? It is a dedicated configuration pin and
  here it routes to the Pico, not to an FPGA IO — so probably not, but worth confirming before
  assuming the Pico is required.
- The flash chip's size and erase granularity. That sets write time, and whether several cores
  could be cached in flash rather than fetched from SD each time.
- Whether `UserCode`/`CheckSum` from the `.fs` header appear in the packed image in a form worth
  checking as well as the IDCODE.
