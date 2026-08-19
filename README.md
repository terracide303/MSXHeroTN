# MSXnano-MiSTle

An MSX2+ core for the **Tang Nano 20K** running on the **MiSTeryShield20k RPi Pico USB** shield.

A fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano), retargeted from the
bare Tang Nano to the MiSTle shield so that the shield's own hardware — its DB9 joystick
port and MIDI sockets — actually works, instead of sitting unconnected.

---

## Status: not working yet. Do not use this.

**This fork has never been synthesized, never been loaded onto a board, and is not usable.**
It exists as a work in progress. If you want a working MSX2+ on a Tang Nano 20K today, use
[upstream MSXnano](https://github.com/Papipapito/MSXnano) — it is complete and tested, and
this fork has nothing to offer you yet.

Specifically, at this point:

- No bitstream has been built from this tree. It may not even synthesize.
- The DB9 code is written but **untested on hardware**. The pin-to-direction mapping is
  derived from MiSTeryNano's RTL rather than measured, so the stick may well move in the
  wrong directions on first try.
- Removing the on-board BL616 path (see below) is a breaking change that has not been
  validated on real hardware.

Nothing here should be flashed to a board you care about until this section says otherwise.

---

## Why this fork exists

Upstream MSXnano targets a bare Tang Nano 20K and drives its USB keyboard through the
board's **on-board BL616** microcontroller. That works, but on a Tang Nano 20K it forces an
awkward arrangement: the board has a single USB-C connector, so a keyboard has to go through
an OTG adapter and a powered hub, which competes with powering the board.

The MiSTeryShield20k solves that in hardware — it carries its own RP2040 companion with a
proper USB host port, plus a DB9 joystick port and MIDI in/out. Upstream constrains **no
pins** for the DB9 or MIDI connectors, so on that shield they are inert.

This fork assumes the shield is present and wires the shield's hardware into the core.

---

## Target hardware

| Part | Notes |
|---|---|
| Sipeed Tang Nano 20K | Gowin GW2AR-18. Developed against a board silkscreened `3923` |
| MiSTeryShield20k RPi Pico USB | Provides the RP2040 companion, USB host, DB9 and MIDI |
| Raspberry Pi Pico | Runs [FPGA-Companion](https://github.com/MiSTle-Dev/FPGA-Companion) as the HID host |
| microSD card | FAT16 or FAT32, holding `.rom` and `.dsk` files |
| HDMI display | Video and audio |

The RP2040 talks to the FPGA over the five `m0s[]` SPI lines. The core switches to it
automatically when CS pulls `m0s[2]` low.

---

## What is different from upstream

### The on-board BL616 path is gone

The shield routes its **DB9 fire-2 line to pin 75**, which upstream uses for `spi_dir`, the
direction line of the on-board BL616 SPI link. Since the shield always brings its own RP2040
companion, that BL616 path is unusable here regardless — so pin 75 is reassigned and
`spi_dir` is dropped.

Consequences, and they are real:

- **This core will not take a USB keyboard from the Tang's own USB-C connector.** HID comes
  from the RP2040 on the shield, or not at all.
- Flashing `fpga_partner` / `fpga_companion` firmware to the Tang's on-board BL616 does
  nothing useful for this core. That whole step is removed from the instructions below.
- On a bare Tang Nano 20K without the shield, this core will boot and show a picture but
  will have **no keyboard**, and is therefore not much use.

If you want the on-board BL616 back, use upstream.

### DB9 joystick (implemented, untested)

The shield's DE9 port is read directly by the FPGA and mixed into PSG port 0 alongside the
USB gamepad, so either input can drive the game.

| `db9[]` | Tang pin | Signal |
|---|---|---|
| 0 | 73 | Fire 1 → TrigA |
| 1 | 74 | Down |
| 2 | 77 | Up |
| 3 | 31 | Right |
| 4 | 49 | Left |
| 5 | 75 | Fire 2 → TrigB |

The lines are active low — a switch to ground, with internal pull-ups — which is already
what MSX PSG Port A expects, so they AND straight into the existing joystick path with no
level conversion. The shield level-shifts them through six `2N7002` FETs in the usual
bidirectional (non-inverting) arrangement, so the polarity survives to the FPGA.

This pin group matches MiSTeryNano's `spare[]` set (its second DB9 port) except for fire-2,
which this shield puts on pin 75 where MiSTeryNano uses 52.

The signal order above is corroborated twice over: it is what MiSTeryNano's `db9_1`
expression in `misterynano.sv` implies, and it is what the shield's own PCB netlist shows —
J1 uses the standard Atari/MSX DE9 pinout (1=Up, 2=Down, 3=Left, 4=Right, 6=Fire1, 9=Fire2)
and the Tang header carries those on consecutive pads in the order Fire1, Down, Up, Right,
Left, Fire2. That is good evidence, but it is still not a substitute for plugging a stick in
and pushing it in four directions.

---

## Plan

**1. DB9 joystick** — code written, awaiting a synthesis run and a bench test.
Verify directions and both fire buttons, and confirm autofire on the USB pad still behaves
now that the DB9 is AND-ed into the same lines.

**2. MIDI in/out, as a Yamaha SFG-05** — not started.

The shield's MIDI hardware is complete and conventional: an `H11L1S` Schmitt opto-isolator
on IN, a `74LVC2G14` buffer on OUT, landing on FPGA pins **71 (out) and 72 (in)**, both
unused by the core. From the FPGA's side MIDI is ordinary asynchronous serial at 31250 baud,
so no extra hardware and no external adapter are needed.

The question is what the MSX thinks it is talking to, and the answer chosen here is the
**Yamaha SFG-05**, the FM Sound Synthesizer Unit from the Yamaha CX5M II.

Why the SFG-05 rather than the alternatives:

- **MSX-MIDI** (8251 USART + 8253 timer, ports E0H/E1H or E8H/E9H) **requires an MSX turbo R
  or later**. This is an MSX2+, so it is out.
- **Philips NMS-1205** works on MSX2, but is an 8251 design and drags in the Y8950.
- The **SFG-01** is MIDI **out only** — it cannot receive external MIDI notes. The SFG-05 is
  the version that added MIDI IN.

The SFG is memory-mapped in a cartridge slot rather than sitting on I/O ports, and the MIDI
half is only two registers:

| Address | Function |
|---|---|
| `0x3FF0` | OPM address register |
| `0x3FF1` | OPM data (write) / OPM status (read) |
| `0x3FF2` | ST0–ST7 output latch / SD0–SD7 input buffer |
| `0x3FF3` | MIDI IRQ vector address |
| `0x3FF4` | External IRQ vector address |
| `0x3FF5` | **MIDI UART data buffer** (read/write) |
| `0x3FF6` | **MIDI UART command (write) / status (read)** |

Addresses are masked with `0x3FFF` inside the 16K page. The YM2148 "MKS" handles MIDI and
the Yamaha keyboard port; from the Z80 it is a data register and a status/command register.
That is considerably less work than an 8251 with a separate baud-rate generator.

### Approach: load it like a cartridge, not a permanent fixture

The SFG claims a **whole primary slot** — its 16K ROM is mirrored across all four pages, which
is why the registers appear at `0x3FF0`, `0x7FF0`, `0xBFF0` and `0xFFF0` alike. It cannot
share a slot with a megaram-loaded ROM. Permanently dedicating a slot to it would be a poor
trade, because only slots 1 and 2 are free and the "Second SCC" option already claims one.

So the SFG is to be **entered deliberately, the way you would plug a cartridge in**: pick the
SFG ROM in the file browser, and the core loads it, enables the SFG decode on a free primary
slot, and resets so the BIOS finds and initialises it. Leave that mode and the slot goes back
to being free.

Note what can and cannot be loaded from SD. The **ROM** comes off the card; the **hardware**
cannot — the YM2148 registers have to be decoded in the fabric, so the logic is always
present and what the menu actually toggles is whether that decode is active. The cost of the
gates is paid whether or not MIDI is in use, which matters on a GW2AR-18 that is already
fairly full. That is the main thing to measure before committing to the OPM.

This fits machinery the core already has: the browser loads `.rom` files with mapper
detection and a manual override, so "SFG" becomes another override type, and launching a ROM
already triggers a reset — which is exactly what the BIOS needs in order to scan the slot and
initialise the cartridge.

### The remaining work

1. **The SFG ROM** holds the driver and BASIC extensions. It is copyrighted, so it comes from
   your own dump on the SD card — which is tidier than baking it into the BIOS pack.
2. **The OPM.** Software expects the FM chip, not just a MIDI port — the SFG-05 uses a YM2164
   (a YM2151 variant with shifted registers). This core already vendors **jtopl** from
   jotego, who also maintains **JT51** for the YM2151, so an OPM core is available from a
   source already present in the tree. Whether it fits alongside everything else is an open
   question.
3. **Slot arbitration.** The SFG and the second SCC+ would compete for the same free primary,
   so they need to be mutually exclusive in the settings menu.

A narrower first step is possible: implement only the YM2148 registers at `0x3FF5`/`0x3FF6`
and leave the OPM out. Software doing plain MIDI output could work, but anything using the
SFG ROM's BASIC extensions will expect the synth to exist. This is also the cheap way to find
out whether the full SFG will fit before investing in JT51.

Reference implementation to work from: openMSX's
[`MSXYamahaSFG.cc`](https://github.com/openMSX/openMSX/blob/master/src/sound/MSXYamahaSFG.cc)
and [`YM2148.cc`](https://github.com/openMSX/openMSX/blob/master/src/serial/YM2148.cc).

**3. Housekeeping** — once the above work, revisit whether the remaining on-board BL616 pins
(13, 48, 76, 86) should be released too, and keep this fork rebased on upstream.

---

## Building

Building the bitstream requires the **Gowin EDA IDE**, which has Windows and Linux builds
only — there is no macOS version. `openFPGALoader` can flash a finished bitstream from a Mac,
but it cannot synthesize one.

```
fpga/Z80_goauld.gprj    Gowin project
fpga/tang9k.cst         pin constraints
fpga/top.v              top level
```

---

## Flashing

Once a bitstream exists, two images go into the Tang's flash. `openFPGALoader` handles both
and runs on Linux, Windows and macOS.

```sh
# core bitstream
openFPGALoader -b tangnano20k -f msxnano.fs

# BIOS pack (MSX2+ BIOS, sub-ROM, Nextor 2.1.4, WiFi ROM)
openFPGALoader -b tangnano20k --external-flash -o 0x200000 --file-type raw goauld_rom_int.bin
```

The Pico on the shield takes stock FPGA-Companion firmware — hold BOOTSEL, plug it into a
computer, and drop `fpga_companion.uf2` (the `BOARD=PICO` build) onto the `RPI-RP2` volume.
No firmware goes to the Tang's on-board BL616.

---

## Using it

Files go in the root of the SD card, or in subdirectories.

| Extension | Loaded as |
|---|---|
| `.rom` | cartridge, into the megaram, with mapper auto-detection |
| `.dsk` | disk image, through Nextor disk emulation |
| `.col` | ColecoVision — also needs `COLECO.ROM` on the card |
| `.sg` | Sega SG-1000 |

Only these extensions are recognised. The boot menu matches the three extension bytes
literally, so a `.mx2` file — a common format for MSX2 cartridge dumps, and byte-identical to
a `.rom` — is **invisible** until renamed.

The file browser starts before the OS. Arrows and RETURN navigate and launch, BS goes back,
`R`/`D`/`A` filter by type, TAB switches partition, `S` opens settings, `W` opens WiFi, and
ESC boots straight to Nextor/MSX-DOS. **F11** toggles turbo; F12 is consumed by the companion
firmware and never reaches the MSX.

---

## Inherited from upstream

Everything not listed above comes from MSXnano unchanged: the Z80, the V9958 VDP with HDMI
output, dual PSG, SCC and SCC+ with an optional second SCC+, OPLL, SD card with Nextor 2.1.4,
ColecoVision and SG-1000 emulation, the ESP-01S WiFi option, and the SD file browser.

For the feature history and per-version release notes, see
[upstream's README](https://github.com/Papipapito/MSXnano) — that history is not duplicated
here, because this fork has not changed any of it.

---

## Credits and licence

**GPLv3**, inherited from upstream.

Fork maintained by [terracide303](https://github.com/terracide303).

Development on this fork is done with AI assistance — **Claude** (Anthropic), via
[Claude Code](https://claude.com/claude-code). The retargeting work, the RTL changes and
this documentation were written with Claude's help and reviewed before committing; commits
produced that way carry a `Co-Authored-By: Claude` trailer, so `git log` shows exactly which
ones. Treat it as it is described above: **unverified on hardware** until someone has run it
on a real board.

- [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano) — the core this forks
- [jabadiagm/MSXgoauldSD_tn20k](https://github.com/jabadiagm/MSXgoauldSD_tn20k) — MSXnano's own basis
- [MiSTle-Dev/FPGA-Companion](https://github.com/MiSTle-Dev/FPGA-Companion) — HID companion firmware
- [MiSTle-Dev/MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) — the shield's DB9 pin assignment and signal order
