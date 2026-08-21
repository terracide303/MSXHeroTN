# MSXnano-MiSTle

An MSX2+ core for the **Tang Nano 20K** running on the **MiSTeryShield20k RPi Pico USB** shield.

A fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano), retargeted from the
bare Tang Nano to the MiSTle shield so that the shield's own hardware — its DB9 joystick
port and MIDI sockets — actually works, instead of sitting unconnected.

---

## Status: working, with one feature outstanding

**It runs on real hardware.** The core synthesizes, boots to the file browser, loads and
plays games, takes a DB9 joystick, and brings up the FPGA-Companion OSD on F12 with working
video, audio and turbo settings. One thing is missing: settings do not persist.

| | State |
|---|---|
| Synthesizes on Gowin EDA | yes |
| Boots, browser, loads and runs ROMs | yes |
| **DB9 joystick** on the shield | **yes** — all directions and both fire buttons |
| BIOS pack, SD browsing, Nextor | yes |
| **OSD overlay (F12)** | **yes** — centred, named MSXHero, settings reach the core |
| **Turbo** | works from the OSD; applied via reset. F11 no longer intercepted, and the crash is gone with it |
| Video and audio settings from the OSD | scanlines, aspect, stereo, second SCC+, volume |
| **Saving settings** | **no** — the companion cannot reach the SD card. See known issues |
| Boot menu | English, titled MSXHero v1.0 |
| **OSD Reset / Cold Boot** | **yes** — verified on hardware |
| Boot logo | own logo works; the v1.9 pack ships the slot blank |
| On-board BL616 HID | removed by design — HID comes from the shield's Pico |
| ESP-01S WiFi, WS2812 LED | given up: their pins are the DB9 lines |

A prebuilt bitstream is in [`compiled/`](compiled/).

### Known issues

**Timing closes again.** `clock_54m` had been missing its 54.000 MHz constraint for several
builds, at worst 50.4 MHz. Restructuring the CPU read mux as a tree fixed it: the current
build closes at **55.626 MHz with zero negative slack on every domain** — more margin than
any earlier build had. See [docs/UTILISATION.md](docs/UTILISATION.md) for how that was
chased, including what did not work.

**Settings do not persist.** The menu's Save writes `msxnano.ini` through the companion's
FatFS, which reaches the SD card via the FPGA's SD target — and `mcu_sdc_din` is tied to zero
here, so the companion cannot see the card at all. Settings apply immediately but are lost at
power-off. This is the outstanding Phase 1 item.

**Turbo is applied by resetting into the new speed**, not switched live — changing CPU
cadence while running hangs the machine. The F11 shortcut is gone: keys belong to the MSX,
machine settings belong in the overlay.

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

| # | Item | State |
|---|---|---|
| 1 | Synthesize on Gowin EDA | done |
| 2 | DB9 joystick | done, verified on hardware |
| 3 | OSD overlay on F12 | done, verified on hardware |
| 4 | Wire the OSD settings to the core | done for reset, turbo, volume, scanlines, aspect, stereo, second SCC+, DB9 port |
| 5 | Persist settings (Save) | **not possible yet** — needs the SD target, see below |
| 6 | Translate the on-screen menu to English | not started |
| 7 | Own boot logo | tooling done; the pack slot is blank by default |
| 8 | Fix the 115-file browser limit | not started |

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

Detail for every item is in **[docs/ROADMAP.md](docs/ROADMAP.md)**.

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
`R`/`D`/`A` filter by type, TAB switches partition, `H` opens help, and ESC boots straight to
Nextor/MSX-DOS. **`F12` opens the OSD** for machine settings; `S` keeps a reduced on-MSX
screen whose only unique job is saving settings to flash, since the OSD's own Save cannot
reach the SD card. The WiFi entry is gone — WiFi is compiled out on this fork. Turbo is set from the OSD, not a keyboard shortcut; F12 is consumed by the companion
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
