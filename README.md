# MSXnano-MiSTle

An MSX2+ core for the **Tang Nano 20K** running on the **MiSTeryShield20k RPi Pico USB** shield.

A fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano), retargeted from the
bare Tang Nano to the MiSTle shield so that the shield's own hardware — its DB9 joystick
port and MIDI sockets — actually works, instead of sitting unconnected.

---

## Status: builds, boots, partly working

**It runs on real hardware.** The core synthesizes, boots to the file browser, and loads and
plays games. It is not finished — two features do not work — but it is no longer vapour.

| | State |
|---|---|
| Synthesizes on Gowin EDA | yes |
| Boots, browser, loads and runs ROMs | yes |
| **DB9 joystick** on the shield | **yes** — all directions and both fire buttons |
| BIOS pack, SD browsing, Nextor | yes |
| **OSD overlay (F12)** | **no** — nothing appears, no crash either. See below |
| **Turbo (F11)** | **crashes the machine** after a few presses |
| Boot logo | slot is blank in the v1.9 pack; adding one is optional |
| On-board BL616 HID | removed by design — HID comes from the shield's Pico |
| ESP-01S WiFi, WS2812 LED | given up: their pins are the DB9 lines |

A prebuilt bitstream is in [`compiled/`](compiled/).

### Known issues

**F12 / OSD shows nothing.** The RTL is in the bitstream and the menu XML has been tried both
ways — served from the core over `sysctrl` CMD 8, and placed on the SD card as `config.xml`
and `msxnano.xml`. Neither produces an overlay, and nothing crashes. Untested next steps: read
the companion's debug output on the Pico's **GP0 at 921600 baud** to see whether it is drawing
an OSD at all, and confirm whether FPGA-Companion **v1.4.21** (what the Pico runs) even has
the "fetch config from the core" path, which was read from a later revision of `main.c`.

**F11 / turbo crashes after a few presses.** Cause unknown, and it is not yet established
whether this is ours or upstream's. Upstream's v1.9 changelog claims to *fix* an F11 hang in
the menu — "the async mux delivered two ENABLE/FALLING in a row to the Z80" — by only
adopting turbo on a clean T-state boundary. Either that fix is incomplete, or something in
this fork interacts with it. Worth testing an unmodified upstream v1.9 build on the same board
to tell the two apart.

---

## Flashing notes learned the hard way

**Take the Tang out of the shield to flash it.** With the shield attached, the FTDI device
enumerates but JTAG fails with `ftdi_usb_reset failed (-6)`. FPGA-Companion can drive JTAG
itself (`jtag.c`, `gowin.c`) and the shield also wires `RECONFIGN`, so something on the shield
contends for those lines. Out of the shield it works every time.

**Do not flash FPGA-Companion firmware onto the Tang's on-board BL616.** Doing so replaces the
factory debugger — the FTDI-compatible `20K's FRIEND` — and openFPGALoader then has nothing to
talk to, on any host. Restore it by flashing
[`friend_20k_encrypted_bl616.bin`](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/src/bl616/friend_20k)
at `0x0` (the encrypted variant, for fused `3923` boards). This costs nothing here, because
this fork does not use the on-board BL616 at all.

---

## Why this fork exists

Upstream MSXnano targets a bare Tang Nano 20K and drives its USB keyboard through the
board's **on-board BL616** microcontroller. That works, but the Tang Nano 20K has a single
USB-C connector and no USB-A, so the one port has to carry power and the keyboard at once.
In practice that means an **OTG adapter and a powered USB hub**, with the hub backfeeding
power to the board.

Which is the point worth making: **that arrangement is not free either.** A powered hub plus
an OTG adapter costs real money, takes two mains outlets between the board and the hub, and
leaves a tangle of adapters on the desk. Against that, the MiSTeryShield20k is not the
expensive option it first appears — it is roughly the same outlay for a tidier machine, and
you get more for it.

The shield solves the problem in hardware: it carries its own **RP2040 companion with a
proper USB host port**, so the keyboard plugs straight in and the Tang's USB-C is left doing
nothing but power. No hub, no OTG adapter, no backfeeding. It also brings a **DB9 joystick
port** and **MIDI in and out** — connectors upstream constrains **no pins** for, so on that
shield they sit inert.

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

### DB9 joystick — working

The shield's DE9 port is read directly by the FPGA and mixed into PSG port 0 alongside the
USB gamepad, so either input can drive the game.

| `db9[]` | Tang pin | Signal |
|---|---|---|
| 0 | 27 | Fire 1  TrigA |
| 1 | 28 | Down |
| 2 | 25 | Up |
| 3 | 26 | Right |
| 4 | 29 | Left |
| 5 | 30 | Fire 2  TrigB |

These are NanoMig's `js0[]` — its "generic IO pins used for DB9 port 1" — confirmed against
this shield's own PCB netlist, where the joystick nets land on **J4 pads 8–13** and pad 14
carries `P31`, anchoring that run of the header to FPGA pins 25–31.

### What this costs

Three of those pins were in use, so this build gives up:

- **The WS2812 case LED** (pin 25) — an *external* addressable LED strip for the 3D-printed
  case, not anything on the Tang itself. Nothing is lost unless you built that case with a
  strip fitted.
- **The ESP-01S WiFi UART** (pins 27/28) — so WiFi over an ESP-01S module is not available on
  this build. The UNAPI ROM is still in the BIOS pack and `wifi_lite` still elaborates; it
  simply has no pins. Reaching WiFi another way is plan item 9.

Both ports are removed from `top.v` and kept as internal wires, so the modules driving them
still elaborate and synthesis prunes them. Leaving them as unconstrained ports would be worse
— Gowin would auto-place them, possibly onto pins that matter.

The lines are active low — a switch to ground, with internal pull-ups — which is already
what MSX PSG Port A expects, so they AND straight into the existing joystick path with no
level conversion. The shield level-shifts them through six `2N7002` FETs in the usual
bidirectional (non-inverting) arrangement, so the polarity survives to the FPGA.



The decode follows NanoMig's `db9_joy0` exactly —
`{!js0[5],!js0[0],!js0[2],!js0[1],!js0[4],!js0[3]}`, i.e. Fire2=`js0[5]`, Fire1=`js0[0]`,
Up=`js0[2]`, Down=`js0[1]`, Left=`js0[4]`, Right=`js0[3]` — since NanoMig demonstrably works
on this shield.

### Companion OSD overlay — implemented, not working

Upstream decoded the OSD SPI channel and discarded the data. This fork renders it: the
128×64 monochrome framebuffer the companion sends is composited onto the picture inside
`v9958_top`, between the VDP's RGB and the HDMI encoder.

The menu itself is served from the core — `sysctrl` CMD 8 streams a gzipped
[`msxnano.xml`](fpga/src/usb/msxnano.xml) out of a 1 KB ROM in the bitstream, so the menu
cannot drift out of step with the core it configures. Regenerate it with
`fpga/src/usb/make_menu_rom.sh` after editing the XML. CMD 4 decodes the ids the menu sets.

`osd_u8g2.v` is vendored unchanged from MiSTeryNano (GPLv3), which is the reference
implementation of this protocol.

The menu carries System (turbo, boot turbo, video standard, keyboard layout, cold boot),
Input (DB9 port, autofire), Video (scanlines, aspect) and Audio (stereo, second SCC+, volume).

**Volume** shows an ASCII bar built out of the entry labels (`[####] 100%`), because
FPGA-Companion renders `<range>` as a number and has no bar widget. A *drawn* bar is possible
but needs a font swap and a firmware rebuild — see
[`pf2bdf.py`](fpga/src/usb/pf2bdf.py), which converts MiSTer `.pf` fonts to BDF for `bdfconv`.
Those fonts are fixed 8×8, which matches the OSD's native 16×8 character grid, and they carry
a solid block at ASCII `0x7F` — a single byte, legal in XML, so it needs no UTF-8 handling.
No font is committed here: Fonts_MiSTer has no licence and its files are traced from arcade
character ROMs, so supply your own as with the BIOS pack. It is implemented
as a shift attenuator on the mixer output, which is exact because the mix is 0-based unsigned
(silence is 0, not mid-scale), so attenuating cannot shift a DC offset and click.

**DB9 port** selects whether the shield's stick answers on MSX joystick port 1 or 2, by
swapping the two ports — games differ on which they read.

Wired so far: **volume** and **DB9 port**. The rest — turbo, boot turbo, scanlines, aspect,
stereo, second SCC+, video standard, keyboard layout, autofire rate — are decoded and
available in `top.v` but not yet merged with `config1_ff`/`config2_ff`, which the `S` menu
drives through I/O ports. Those two were done first because they touch only the audio mixer
and the joystick mux, not the boot config path.

---

## Plan

Split into two phases. **Phase 1 is getting a working port** — build what is already written,
prove it on hardware, and do only the easy things that make it pleasant to use. **Phase 2 is
everything else.** Nothing from Phase 2 starts before Phase 1 boots.

### Phase 1 — a working port

| # | Item | State | Why it is Phase 1 |
|---|---|---|---|
| 1 | **Synthesize it** on Gowin EDA | done | Still want the utilisation figure from the build report — no one has ever had one for this core |
| 2 | **Bench-test the DB9** | done, works | Pins were wrong at first; corrected to NanoMig's `js0[]` group |
| 3 | **Make F12 / the OSD work** | shows nothing | Next: read the Pico's debug UART on GP0 at 921600 baud |
| 3b | **Fix the F11 turbo crash** | new | Establish first whether stock upstream v1.9 does it too |
| 4 | **Connect the OSD settings** to `config1_ff`/`config2_ff` | not started | The menu currently accepts input without changing anything — the last hop |
| 5 | **Translate the on-screen menu** to English | not started | Most visible thing in the fork, and no RTL risk |
| 6 | **Replace the boot logo** | not started | It is another group's identity mark. No RTL risk |
| 7 | **Fix the 115-file browser limit** | not started | A real bug: files past 115 are invisible with no warning |

### Phase 2 — the extras

| Item | Size | Notes |
|---|---|---|
| **MIDI as a Yamaha SFG-05** | large | Loadable cartridge mode. Needs a slot, the SFG ROM, and probably an OPM |
| **USB mouse** | small | `hid.v` already has it; `fpga_companion.v` has the line commented out |
| **`.CAS` cassette** | medium | `MSX1_MiSTer/rtl/tape.sv` is reusable (GPL v2+) |
| **Persist SRAM saves** | medium | Fix `flash_rw.v`'s `write_terminate` first |
| **WiFi without the ESP-01S** | research | Depends on `at_wifi.c`'s AT dialect and whether the Pico is a W |
| **Drawn OSD bar + 8×8 font** | small, parked | Costs a companion firmware fork |
| **Backports from MSXimus** | small–medium | Audio remaster, 2 MB ASCII16, master volume, CRT borders |
| **Configurable mapper engine** | large | Carnivore2+'s register-driven approach, arrived at independently |
| **Swap to an MIT V9958** | medium | Resolves the GPL-3.0 licence inconsistency; source is HRA!'s FPGA_MSXtR |
| **Translate the Spanish comments** | large | 13 files; conflicts with rebasing onto upstream |
| **Housekeeping** | small | Release pins 13/48/76/86, keep rebased on upstream |

### Detail


*[Phase 1]* **1. DB9 joystick** — **done, and verified on hardware.**
All four directions and both fire buttons work. Still unverified: that autofire on the USB
pad's buttons 3/4 still behaves now the DB9 is AND-ed into the same lines.

*[Phase 2]* **2. MIDI in/out, as a Yamaha SFG-05** — not started.

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

*[Phase 1]* **3. Remove the 115-file limit in the browser** — not started.

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

*[Phase 1]* **4. Render the companion OSD overlay** — **implemented, but not working.**

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

*[Phase 1]* **5. Translate the on-screen menu to English** — not started, and the most user-visible item
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
"Ajustes"  "Settings" is longer, so it cannot be assumed.

This is worth doing early: it is the part of the fork every user sees, and it is independent
of the DB9 and MIDI work.

*[Phase 1]* **6. Boot logo** — the problem resolved itself; adding one is optional.

The boot screen used to show the **MSX Barcelona** user-group logo, which this fork has no
affiliation with. It is **already gone**: upstream's v1.9 BIOS pack ships the logo slot
(`0x7C000`–`0x80000`) blank — all `0xFF` where v1.8 had the `LG` magic and 6120 bytes of
image. The menu checks that magic before calling the logo routine, finds nothing, and skips
it. So the concern is settled and what follows is only for adding a logo of your own.

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

*[Phase 2]* **7. Translate the Spanish comments and docs to English** — not started.

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

*[Phase 2]* **8. Drawn OSD bar and a fixed 8×8 font** — **parked.** Decided against for now: get
everything working on stock FPGA-Companion firmware first.

The volume bar is currently ASCII (`[####] 100%`) because the stock firmware has no bar
widget. A drawn bar is achievable, and the groundwork is already in the repo — but it costs a
firmware fork, so it waits until the core actually runs.

What it would take, when the time comes:

- **The font.** MiSTer's `.pf` fonts are fixed 8×8, which is the OSD's native grid
  (`osd_u8g2.v` is 16×8 characters over 128×64) where the stock proportional face sits
  off-grid. They already carry a solid block at ASCII `0x7F` — a single byte, legal in XML,
  so it needs no UTF-8 handling and no change to `menu.c`'s 22 `DrawStr` call sites.
  [`pf2bdf.py`](fpga/src/usb/pf2bdf.py) converts one to BDF for `bdfconv`, and `--blocks`
  appends a matching hollow square for the empty half of the bar.
- **One line in `menu.c`** — the `u8g2_SetFont` call — then rebuild the `.uf2` and reflash
  the Pico.

Two costs to weigh at that point. It means **maintaining a firmware fork**, giving up
free upstream fixes, though the diff is small enough to rebase indefinitely. And a fixed 8×8
font imposes a hard **16 characters per line**, so labels like `Second SCC+:` would need
shortening — a menu redesign, not a drop-in.

No font is committed here: Fonts_MiSTer has no licence and its files are traced from arcade
character ROMs, so supply your own as with the BIOS pack.

*[Phase 2]* **9. WiFi — research, not yet a decision.** Today WiFi needs an **ESP-01S** wired to pins
27/28, pre-flashed with its own UNAPI firmware. There may be a way to drop that module
entirely, but enough is unknown that it needs investigating before it becomes a plan.

**What we know:**

- FPGA-Companion ships [`at_wifi.c`](https://github.com/MiSTle-Dev/FPGA-Companion/blob/main/src/at_wifi.c),
  which implements a Hayes **AT-command modem over the FPGA "port" interface** — the same
  `sysctrl` CMD 7 mechanism this core already has plumbing for (`port_out_available`,
  `port_out_data`, `port_in_data`).
- So in principle the MSX's UNAPI byte stream could be routed to the companion over SPI
  instead of out to pins 27/28, and a **Pico W** could provide the network itself. That
  would remove the module, its four jumper wires and its separate `esptool` flashing step,
  and free two pins.
- The companion already reads an `.ini` from SD (`inifile.c`), which is where credentials
  would live — as MiSTeryNano does it.
- **WiFi credentials cannot go in the OSD.** The XML vocabulary has no text-entry widget, and
  CMD 4 carries a single byte per id, so it could not transport an SSID or password. On/off
  toggles, a reconnect button and a fixed pick-list are expressible; configuration is not.
  Credential entry stays in the core's own `W` menu.

**What we do not know:**

- Whether `at_wifi.c` speaks enough of the **ESP8266 AT dialect** for the bundled
  `esp8266e.rom` UNAPI ROM to talk to it. The ROM expects specific ESP-AT responses at a
  fixed **859372 bps**. If it does not, either `at_wifi.c` grows or the UNAPI ROM is replaced
  — and that is the whole risk of the idea.
- Whether the Pico on the shield is a **Pico W**. The published `fpga_companion.uf2` is built
  with `PICO_BOARD=pico_w` and `ENABLE_WIFI`, but a plain Pico has no radio, and this route
  is dead without one.
- Whether the shield exposes what the radio needs, and what it costs in companion firmware
  CPU time alongside USB host duty.
- Whether the baud rate matters at all once the link is SPI rather than a real UART.

**Also worth comparing:** MSXimus (the same author's Console 60K core) moved to an
**ESP32-C6** with an optional info display, rather than staying on the ESP-01S. That may be
the better answer regardless of what the companion can do.

*[Phase 2]* **10. USB mouse** — not started, and the cheapest real feature on this list.

`hid.v` already exposes a mouse, and `fpga_companion.v` has the connection **commented out**:

```verilog
//.mouse(hid_mouse),
```

So the companion is receiving USB mouse data and the core is discarding it. What is missing
is the MSX side: the MSX mouse is read through the PSG joystick port as a quadrature-style
protocol, so the joystick mux needs a mouse mode alongside the DB9 and USB pad paths already
there.

Worth doing early because the MSX mouse is the platform's main non-joystick input — Graphos 3,
Dynamic Publisher and the art and CAD software all expect it, and none of it is usable today.

*[Phase 2]* **11. `.CAS` cassette support** — not started.

There is none: the boot menu matches only `ROM` and `DSK`, and nothing in the core handles
tape. A large part of the MSX1 library exists only as `.cas`, so this widens what the machine
can actually run rather than adding hardware it does not have.

**There is a reference implementation to work from:**
[`MSX1_MiSTer/rtl/tape.sv`](https://github.com/MiSTer-devel/MSX1_MiSTer/blob/master/rtl/tape.sv)
by molekula — 191 lines, **GPL v2 or later**, so compatible with this project.

It takes the faithful route rather than hooking the BIOS: it streams the `.CAS` out of RAM
and **generates the cassette bitstream itself**, presenting a single `cas_out` bit to the
MSX's cassette input so the real BIOS does the decoding. Loaders that bypass the tape hooks
therefore still work. Its state machine is `INIT  SEARCH  PLAY_SILENT  PLAY_SYNC
PLAY_DATA`, it recognises the CAS block marker, frames each byte as `{2'b11, data, 1'b0}`,
and encodes bits as the usual 1200/2400 Hz pair from a baud divider.

Porting it needs three things beyond the module itself: somewhere to hold the `.CAS` (the
megaram, or streamed from SD), the `cas_out` bit wired to the MSX's cassette input, and
`.CAS` added to the browser's extension matching — which today accepts only `ROM` and `DSK`.

Its `play` and `rewind` inputs are a natural fit for **OSD buttons**, which is one of the few
places the overlay can do something the core's own menu cannot do as neatly.

**Cost.** Counted from the RTL: `state` 3 bits, `ram_a` 27 (≈19 would do — a `.cas` is a few
hundred KB), `counter` 11, `byte_out` 11, `baud_div` 11, `byte_pos` 4, `cnt` 2, plus about
eight flags; combinationally a few comparators and an 8:1 byte mux for the signature. So
**roughly 100–200 LUT4s and ~85 registers, no BSRAM and no DSP** — a fraction of a percent
here. It also lives in a slow clock domain, so unlike the OSD compositor it is no threat to
timing closure. The `.cas` itself rides the megaram path the ROM loader already uses, so
storage costs a mux rather than new memory.

### Decided approach

**Phase 1 — convert `.CAS` to `.DSK` on the host.** Zero core changes, works today through the
Nextor path that already exists. Note also that much MSX1 tape software has already been
dumped as `.rom` or `.dsk`, so the marginal gain from native `.cas` is smaller than it looks.

**Phase 2 — port `tape.sv`.** Cheap, faithful, handles loaders that bypass the BIOS, and
reuses machinery that is already here.

**Rejected: hooking the BIOS tape calls** (`TAPION` `0x00E1`, `TAPIN` `0x00E4`, `TAPOOF`
`0x00E7`). It gives instant loading and costs almost no logic, but it is the worst trade of
the three: it saves ~150 LUTs, which is irrelevant, while requiring a patched BIOS built from
ROMs the user must supply, and it fails on exactly the custom turbo loaders that justify
doing any of this. The only thing it buys over `tape.sv` is speed.

**The speed caveat.** `tape.sv` loads at real tape speed — minutes per game. Moving to 2400
baud (which the MSX supports natively) and stacking turbo on top helps, but it stays slow. If
instant loading matters more than loader compatibility, the `.dsk` route already provides it.

*[Phase 2]* **12. Persist SRAM saves** — not started.

The core already has cartridge SRAM for ASCII8 and ASCII16 — it lives in the top 32 KB of the
megaram, gated by port `#43`. But it is **volatile**: saves in Hydlide 3, Xanadu, the Koei
games and anything else with a battery-backed cartridge are lost at power-off.

Upstream has a design for this in `SRAM_PERSIST_CONSOLE60K_DESIGN.md`, though it targets the
Console 60K. **Read the audit first**: `AUDIT_PRE_PORT_60K.md` records that this plan reuses
`flash_rw.v`, and that `flash_rw.v:24` has `write_terminate` declared `output` and never
assigned, so PAGE PROGRAM always writes all 256 bytes. That bug is benign today and is not
benign here — it must be fixed before anything relies on that writer.

*[Phase 2]* **13. Swap to an MIT-licensed V9958** — not started.

This is a **licence fix** that happens to also be a component swap. The core's video path is
`tn_vdp_v3_v9958/`, which contains Ohnaka's `vdp_vga.vhd` — one of the two files behind the
GPL-3.0 inconsistency recorded in [FINDINGS](docs/FINDINGS.md), since it forbids commercial
use without written permission.

[`hra1129/FPGA_MSXtR`](https://github.com/hra1129/FPGA_MSXtR) ships a V9958 under **MIT**
(`fpga/FPGA_MSXtR/src/v9958`), by the author of the V9968. Swapping to it would leave only the
OCM-derived files under `fpga/src/ocm/` to deal with.

Not a small change: the current VDP also carries the HDMI encoder, scanlines, aspect
signalling and the OSD compositor added by this fork, so all of that has to be re-attached or
replaced. `FPGA_MSXtR` has its own `hdmi_tx` and `i2s_audio`, also MIT, which may be the
cleaner path than grafting.

Its `labo/` tree — twenty-odd self-contained Gowin projects, each isolating one problem
(`CPU_000`–`006`, `VDP_000`–`009`) — is a good model for trying this in isolation rather than
against the working core, and a source of known-good reference projects when something
confusing turns up.

Also MIT and possibly useful from the same repo: `cr800` (an R800), a Tang Nano 20K SDRAM
controller, `opll`, `ssg`, `rtc`, and `micom_connect` — his MCU link, which is the same
Pico-as-companion pattern used here.

*[Phase 2]* **14. Housekeeping** — once the above work, revisit whether the remaining on-board BL616 pins
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
