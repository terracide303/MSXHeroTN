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

**3. Remove the 115-file limit in the browser** — not started.

The file browser silently shows only the **first 115 entries of any directory**. On a card
with a few hundred ROMs in the root, everything past 115 is invisible with no warning that
anything is missing.

```asm
MAX_ENT  equ  115    ; array capacity (115*80 = 9200 bytes -> C300..E6F0)
```

The listing is built into a fixed array in MSX RAM, 80 bytes per record, and the scan stops
when it fills. Raising the constant alone does not help: `ENT_ARRAY` occupies `C300–E6F0`
and `PART_TBL` sits immediately above at `E800`, so even claiming everything up to the system
area yields roughly 155 entries. The record size is the real constraint, and `NAME_MAX` of 70
dominates it.

Three approaches, cheapest first:

1. **Shrink the record.** Store the 8.3 name plus the directory entry's location (LBA +
   offset) and re-read the long name only for the highlighted row. About 24 bytes per record,
   so roughly 383 entries. Buys headroom, does not remove the ceiling.
2. **Stream the directory.** Keep only the visible 18 rows plus a stack of page-start
   positions and re-read from the card while scrolling. Unbounded, and clean here because the
   listing is in raw FAT order with no sort to maintain. Costs one SD read per scroll.
3. **Put the array in the megaram.** The preferred option. The menu already writes to the
   megaram — that is how it loads ROMs — so the bank-switching path exists. At 80 bytes per
   record, 2 MB holds on the order of 26,000 entries, MSX RAM is untouched, and the megaram
   is free scratch until a ROM is actually launched.

Whichever is chosen, the browser should also **say when a listing was truncated** rather than
just stopping, which is the part that makes the current behaviour confusing.

Until this is fixed, the workaround is subdirectories: the cap is per directory, so folders of
under 115 files each keep everything reachable.

**4. Render the companion OSD overlay** — code written, untested.

FPGA-Companion draws its own on-screen display — the overlay other MiSTle cores use for
settings, opened with F12 — and ships it to the FPGA as a 128×64 monochrome framebuffer over
SPI. Upstream received it and threw it away. This fork now wires it up:

- `osd_u8g2.v` vendored from MiSTeryNano (GPLv3, the reference implementation of this
  protocol) into `fpga/src/usb/`.
- `fpga_companion.v` exports the OSD byte stream (`osd_strobe`/`osd_start`/`osd_data`)
  instead of leaving `mcu_osd_strobe` dangling.
- The compositor is instantiated **inside `v9958_top`**, because RGB never surfaces at the
  top level — it sits between the VDP's `VideoR/G/B` and the `dvi_*` signals feeding the HDMI
  encoder, ahead of the scanline stage so the OSD dims with the picture rather than floating
  over it. `VideoHS_n`/`VideoVS_n` go in unmodified — `osd_u8g2` takes **active-low** sync
  despite its port names, which is how MiSTeryNano and NanoMig both wire it.

Still to verify on hardware: that F12 actually produces a centred overlay, and that adding a
module to the pixel-clock domain does not upset timing closure on a device that is already
fairly full.

The menu **content** path is now built too: `sysctrl` implements **CMD 8**, streaming the
gzipped `msxnano.xml` out of a 1 KB ROM in the bitstream, so the menu travels with the core
and needs no file on the SD card. `make_menu_rom.sh` regenerates it (444 bytes gzipped, 580
spare). **CMD 4** decodes the ids the menu sets — turbo, boot turbo, scanlines, aspect,
stereo, second SCC+, reset — replacing the vestigial Atari ST ids upstream left behind.

What is **still missing** is the last hop: those `system_*` values are decoded but not yet
connected to the core's own config registers. Today `config1_ff`/`config2_ff` are driven by
the `S` menu writing I/O ports, and merging two sources of truth needs a policy decision
rather than more wiring — so the OSD will show its menu and accept input before it changes
anything. That is deliberately left as a separate change, since it touches the boot config
path.

The plumbing is half-built. `mcu_spi_new.v` already decodes the OSD channel:

```verilog
assign mcu_osd_strobe = spi_in_strobe && spi_target == 8'd2;
```

but in `fpga_companion.v` the data input is tied off and the strobe is consumed by nothing:

```verilog
.mcu_osd_din(8'b00000000),
```

So F12 currently does nothing visible: the companion swallows the key for its OSD — which is
why upstream moved turbo to F11 — draws the overlay, sends it, and the core discards it.

What is needed: a 1 KB framebuffer (128×64 bits) written by the OSD strobe, and a compositor
in the video path to overlay it on the HDMI output. The video chain is
`tn_vdp_v3_v9958/src/hdmi/*` plus `vdp_vga.vhd`.

Two things to decide before building it. This core already has its own settings menu on `S`
and a full SD browser, so the companion OSD would **overlap** rather than replace them — it is
worth deciding what belongs in each rather than ending up with two menus that disagree. And
`vdp_vga.vhd` (Ohnaka) **prohibits commercial use without written permission**, which
constrains what a modified video path can be redistributed as.

**No FPGA-Companion fork is needed.** The firmware is core-agnostic: the core identifies
itself over SPI, and the companion loads its entire menu from an XML file — first looking for
it on the SD card, and falling back to asking the core to serve it (`main.c`). So the menu is
defined by data you write, not by C you maintain. A draft lives at
[`fpga/src/usb/msxnano.xml`](fpga/src/usb/msxnano.xml) with System, Video and Audio menus —
turbo, boot turbo, scanlines, aspect, stereo, second SCC+, reset and cold boot — and
deliberately no file selectors, since the core's own browser does that better.

Serving it from the core means implementing `sysctrl` **CMD 8** ("read menu config"), which
upstream left as an empty block. The ids the menu sets arrive back via **CMD 4**, which also
needs connecting to the config registers the `S` menu currently drives through I/O ports.

Upstream's `fpga/GRAPHICAL_FRONTEND_DESIGN.md` explores a richer version of this idea (cover
art, a full framebuffer) but targets the Console 60K. The plain 128×64 overlay is the modest,
achievable version of the same thing.

**5. Translate the on-screen menu to English** — not started, and the most user-visible item
on this list.

The entire boot menu UI is in Spanish — the status bar, the help screen, every prompt and
error message:

```
"R/D/A=Filtro  ESC=Boot  S=Set  W=WiFi  TAB=Part  H=Ayuda"
"Arriba/Abajo          : mover (Izq/Der = pagina)"
"Cargando ROM en megaram..."
"DSK fragmentado: copialo de nuevo. Pulsa tecla"
```

There are **99 string literals** in `fpga/src/msxnano_menu/src/menu_main.asm`. This is not a
plain find-and-replace, because many are **width-locked**:

- Some are padded to a fixed column count, and come in same-length pairs that must stay
  matched — `"RETURN=LANZA M=MAPPER S=SRAM ESC"` and `"RETURN=LANZA M=MAPPER ESC       "`
  are both exactly 32 characters.
- The help screen is column-aligned, with the `:` of every line in the same column.
- The status bar is 57 characters and has to keep fitting the screen width.

So each translated string has to fit its original footprint, or the layout has to be adjusted
deliberately along with it. English is usually shorter than Spanish, which helps, but
"Ajustes" → "Settings" is longer, so it cannot be assumed.

This is worth doing early: it is the part of the fork every user sees, and it is independent
of the DB9 and MIDI work.

**6. Replace the boot logo** — not started.

The boot screen shows the **MSX Barcelona** user-group logo. This fork has no affiliation
with that group, so shipping their identity mark is not appropriate regardless of taste —
it needs replacing with something of this project's own.

The pipeline is self-contained:

```
fpga/src/rom/logo_site.webp   ->   make_logo16k.py   ->   logo16k.bin
```

`logo16k.bin` is a 16 KB image for slot 0-3 page 1, laid out as
`[magic 'LG'][Z80 routine @4002][32-byte palette][image, 2 px/byte]`, which the menu invokes
with `CALLF 0x8C:4002` once it has verified the magic. `build.bat` then concatenates it into
the BIOS pack.

```sh
python make_logo16k.py my_logo.png [background_hex]
```

Constraints on a replacement image:

- Output is **MSX SCREEN 5** — 256 pixels wide, 16 colours, 2 pixels per byte.
- The whole thing must fit 16 KB including the routine and palette, which caps the image at
  roughly **256×126**. The source is 512×512 and gets scaled.
- The background colour is passed as a hex argument and is used for the border too.

One dependency worth knowing: changing the logo means **rebuilding the BIOS pack**, and
`build.bat` assembles it from MSX system ROMs that are not in this repository. So this needs
your own ROM dumps, not just a new image.

**7. Translate the Spanish comments and docs to English** — not started.

Upstream is written in Spanish throughout its comments and design documents. This fork is
worked on in English, and mixed-language sources are a genuine hazard when the comments are
the only explanation of why a piece of timing-sensitive code is the way it is.

Thirteen files carry meaningful Spanish. In the order it should be tackled:

| File | Lines | Notes |
|---|---|---|
| `fpga/top.v` | 2808 | Comments only, and the file this fork actively edits. Start here. |
| `fpga/src/megaram.v`, `fpga/src/memory.v` | 271 / 464 | Comments only. |
| `fpga/src/msxnano_menu/src/menu_main.asm` | 8235 | The largest by far, and the boot menu the SFG work will have to touch. |
| `tools/` (`scctest.asm`, test benches, ROM scripts) | — | Low risk, low urgency. |
| The three inherited design docs | 86 / 257 / 136 | Prose only. Lowest priority — they are already marked out of scope. |

Two rules for this work, because it is the kind of change that silently breaks things:

- **Translate comments only. Not one instruction, label, or string literal changes.** In
  `menu_main.asm` in particular, a renamed label or an altered message length is a bug, and
  assembly gives no warning.
- Do it in **separate commits from functional changes**, so a translation pass never hides a
  behavioural edit in a large diff.

**8. Housekeeping** — once the above work, revisit whether the remaining on-board BL616 pins
(13, 48, 76, 86) should be released too, and keep this fork rebased on upstream.

Note that translation and rebasing pull against each other: the more of upstream's comments
are rewritten here, the more conflicts a future `git merge upstream/main` produces. Worth
weighing before translating files upstream is still actively changing.

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

**Only those two.** Upstream v1.9 removed ColecoVision and Sega SG-1000 support — the RTL,
the SN76489 core and the menu's `.COL`/`.SG` handling all went — so this fork does not have
them either. If you want them back, see the note below.

The boot menu matches the three extension bytes literally, so a `.mx2` file — a common format
for MSX2 cartridge dumps, and byte-identical to a `.rom` — is **invisible** until renamed.

The file browser starts before the OS. Arrows and RETURN navigate and launch, BS goes back,
`R`/`D`/`A` filter by type, TAB switches partition, `S` opens settings, `W` opens WiFi, and
ESC boots straight to Nextor/MSX-DOS. **F11** toggles turbo; F12 is consumed by the companion
firmware and never reaches the MSX.

---

## Inherited from upstream

Everything not listed above comes from MSXnano unchanged: the Z80, the V9958 VDP with HDMI
output, dual PSG, SCC and SCC+ with an optional second SCC+, OPLL, SD card with Nextor 2.1.4,
the ESP-01S WiFi option, and the SD file browser.

### Console emulation was removed upstream

MSXnano up to v1.8 could also run **ColecoVision** and **Sega SG-1000** games. Upstream's v1.9
(`ce46ef9`, "MSX-only cleanup") deleted all of it: `console_mode` came out of `top.v`, the
console memory map came out of `megaram.v`, `sn76489.v` was deleted and dropped from
`build.tcl`, and the menu lost `.SG`/`.COL` detection, launching, `COLECO.ROM` and its
strings. This fork inherits that state.

It is recoverable rather than lost — the code is one commit back in history, so restoring it
means reverting a known change rather than writing anything new:

```sh
git show ce46ef9 --stat        # what was removed
git checkout ce46ef9^ -- fpga/src/sn76489.v
```

That matters for more than nostalgia. The SN76489 and the TMS9918-compatible modes of the
V9958 are exactly what the wider **Z80 + TMS9918 + SN76489** family of machines needs — Sord
M5, Memotech MTX, Sega SC-3000 — so bringing the console path back is also the groundwork for
anything else in that family.

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
