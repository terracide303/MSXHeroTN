# Findings

Everything established while retargeting MSXnano to the MiSTeryShield20k, with the evidence
for each claim. Recorded so none of it has to be re-derived, and so the wrong turns are not
taken twice.

Anything marked **unverified** was established by reading code or schematics, not by running
it. Nothing in this fork has been synthesized.

---

## 1. The Tang Nano 20K board

### `3921` and `3923` are different boards

| Marking | BL616 eFuse | Consequence |
|---|---|---|
| unmarked (early) | not fused | Cannot run encrypted `fpga_partner`; also has the C51 capacitor flaw blocking SPI |
| `3921` | often **not** fused | On-board BL616 frequently cannot run companion firmware — hence the "use an M0S Dock" advice |
| `3923` | **fused** | Companion firmware works, JTAG survives, but **different BL616 SPI pins (MISO/MOSI)** |

`3923` support exists only in **FPGA-Companion v1.4.22** (`bl616_fpga_partner_nano20k_v3923.bin`,
`fpga_companion_nano20k_v3923.bin`, both at the usual `0x0` / `0x40000`). Upstream MSXnano
bundles v1.4.21, which has no `3923` support at all — its firmware yields a working picture
and a **dead keyboard**, which is a confusing failure because video comes from the FPGA and
is unaffected.

Source: [MiSTle-Dev version wiki](https://github.com/MiSTle-Dev/.github/wiki/Versions_TangNano20k),
FPGA-Companion v1.4.22 release notes.

### Connectors

The board has **one USB-C and no USB-A**. Upstream's connection diagram and BOM both show a
USB-A host port for the keyboard; it does not exist. On a bare Tang this forces an OTG
adapter plus a powered hub, because the single connector must carry power and the keyboard at
once. The shield removes that problem by bringing its own host port.

### Entering BL616 ISP mode

**S2 is not the BL616 button.** Upstream's diagram labels it `S2: UPDATE (BL616 ISP mode)`,
which is wrong:

- **S2** — used when programming the **FPGA** flash (hold while plugging in)
- **BOOT** — a separate button, bottom-left near the USB-C, for **BL616** ISP mode

The reliable test for whether ISP mode was entered, on macOS: ports change from **two
`/dev/tty.usbserial-*`** (the normal FT2232-style JTAG+UART emulation) to **one
`/dev/tty.usbmodem*`** (the BL616 ROM bootloader as a CDC device). If you still see the pair,
the button press did not take.

---

## 2. Flashing from macOS

Neither Gowin Programmer nor Bouffalo Dev Cube has a macOS build. Both have working
replacements.

**FPGA** — `openFPGALoader` (`brew install openfpgaloader`):

```sh
openFPGALoader -b tangnano20k -f msxnano.fs
openFPGALoader -b tangnano20k --external-flash -o 0x200000 --file-type raw goauld_rom_int.bin
```

`flash chip unknown: use basic protection detection` is a benign warning.

**BL616** — `bflb-mcu-tool`, with two traps:

- It still imports `telnetlib`, removed in Python 3.13, so it **must run under an older
  Python** (macOS's `/usr/bin/python3` at 3.9 works; Homebrew's 3.14 does not).
- It **exits 0 even when the burn fails**, so its log has to be scraped for
  `handshake failed` / `ErrorCode` / `retry failed`.
- The chip **resets out of ISP mode after each successful burn**, so the two stages cannot
  run back to back — BOOT mode must be re-entered between them.

---

## 3. The MiSTeryShield20k RPi Pico USB

Sources: `Boards-main/misteryshield20k_rpipico/MiSTeryShield20kRPiPicoUSB.kicad_sch` and
`.kicad_pcb`.

### DB9 joystick

The DE9 (J1) uses the standard Atari/MSX pinout — pad 1 Up, 2 Down, 3 Left, 4 Right, 6 Fire1,
9 Fire2 — level-shifted through **six `2N7002` FETs** in the usual bidirectional arrangement,
which is **non-inverting**, so active-low survives to the FPGA.

| `db9[]` | Tang pin | Signal |
|---|---|---|
| 0 | 73 | Fire 1 |
| 1 | 74 | Down |
| 2 | 77 | Up |
| 3 | 31 | Right |
| 4 | 49 | Left |
| 5 | **75** | Fire 2 |

This is MiSTeryNano's `spare[]` group (its *second* DB9 port) except that fire-2 is on **75**
where MiSTeryNano uses **52**. Pin 75 is `spi_dir` upstream, which is why this fork drops the
on-board BL616 path.

The order is corroborated twice: it is what `db9_1` in `misterynano.sv` implies —

```systemverilog
wire [5:0] db9_1 = { !spare[5], !spare[0], !spare[2], !spare[1], !spare[4], !spare[3] };
```

— and it is what the PCB netlist shows, with the Tang header carrying the lines on
consecutive pads in the order Fire1, Down, Up, Right, Left, Fire2. **Still unverified** by
pushing a real stick.

### MIDI

Electrically complete and conventional: **`H11L1S`** Schmitt opto-isolator on IN with a
`1N4148W`, **`74LVC2G14`** buffer on OUT, landing on **pins 71 (out) and 72 (in)** — both
unused by MSXnano. The FPGA sees ordinary 3.3 V UART at 31250 baud. No external hardware
needed.

---

## 4. MIDI on the MSX

MIDI is only asynchronous serial; the difficulty is entirely *which interface* the software
thinks it is talking to.

| Interface | Hardware | Addressing | Era |
|---|---|---|---|
| **MSX-MIDI** internal | 8251 USART + 8253 timer | I/O `E8H`/`E9H`, counters `ECH`–`EFH` | **turbo R only** |
| **MSX-MIDI** external | same | I/O `E0H`/`E1H`, config `E2H` | turbo R only |
| **Philips NMS-1205** | 8251 + Y8950 | I/O | MSX2 |
| **Yamaha SFG-01** | YM2151 + YM2148 | memory-mapped | MSX1 (CX5M) |
| **Yamaha SFG-05** | YM2164 + YM2148 | memory-mapped | MSX1 (CX5M II) |

**MSX-MIDI requires an MSX turbo R or later**, so it is out for an MSX2+. The **SFG-01 is
MIDI-out only** — it cannot receive external notes. **SFG-05** is the target.

The SFG is memory-mapped in a cartridge slot, masked with `0x3FFF`:

| Address | Function |
|---|---|
| `0x3FF0` | OPM address register |
| `0x3FF1` | OPM data (w) / status (r) |
| `0x3FF2` | ST0–ST7 out latch / SD0–SD7 in buffer |
| `0x3FF3` | MIDI IRQ vector |
| `0x3FF4` | External IRQ vector |
| `0x3FF5` | **MIDI UART data** |
| `0x3FF6` | **MIDI UART command (w) / status (r)** |

So the MIDI half is **two registers** — far less work than an 8251 with a separate baud
generator. It claims a **whole primary slot**: openMSX declares `mem base 0x0000 size 0x10000`
with the 16K ROM mirrored, which is why the registers repeat at `0x7FF0`, `0xBFF0`, `0xFFF0`.

Reference: openMSX
[`MSXYamahaSFG.cc`](https://github.com/openMSX/openMSX/blob/master/src/sound/MSXYamahaSFG.cc),
[`YM2148.cc`](https://github.com/openMSX/openMSX/blob/master/src/serial/YM2148.cc),
[MSX-MIDI on MAP](https://map.grauw.nl/resources/midi/msx-midi.php).

---

## 5. FPGA-Companion

### No fork is needed to customise it

`main.c` identifies the core over SPI, then loads the **entire menu from an XML file** — first
looking on the SD card, then falling back to asking the core to serve it:

```c
// try to load a config .xml from sd card. If the core has identified itself,
// then e.g. atarist.xml will be read. otherwise config.xml
if(f_open(&fil, sys_get_config_name(), ...) == FR_OK) { ... }
else { /* no XML on SD card, try to load from core itself */ }
```

The element vocabulary is `menu`, `list`/`listentry`, `toggle`, `range`, `fileselector`,
`image`, `button`, and `actions` containing `set`, `load`, `save`, `delay`, `link`, `hide`.
Each control carries a one-character `id` whose value is pushed to the core.

### sysctrl commands used here

- **CMD 4** — config values set via the OSD: byte 1 is the id character, byte 2 the value.
- **CMD 8** — the core streams its menu XML out, one byte per read, address reset when the
  command byte arrives. MiSTeryNano stores it **gzipped** in a 1 K ROM:
  `gzip -n atarist.xml; xxd -c1 -p atarist.xml.gz > atarist_xml.hex`.

### OSD framebuffer protocol

128×64 monochrome, 1024 bytes, organised "vertically" like a small OLED so u8g2 can address
it. Commands on target 2: **1 = enable** (one byte, bit 0 shows/hides), **2 = write** (a tile
address byte then N data bytes).

**`SPI.md`'s prose about the tile address is misleading — go by the code.**
`osd_u8g2.c` sends `((y/8)<<4) + x/8`, and the RTL consumes it as
`data_cnt <= {data_in[6:0], 3'b000}`. Those agree; the prose does not.

### `osd_u8g2.v` takes **active-low** sync

Despite ports named `hs`/`vs`. Its own comments give it away — a rising edge on `hs` is the
*"end of hsync"*, a falling edge on `vs` the *"begin of vsync"*, which only holds for
active-low signals. Both MiSTeryNano (`src/tang/nano20k/video.v`, `.hs(sd_hs_n)`) and NanoMig
(`src/tang/nano20k/top.sv`, `.hs(hs_n)`) feed it unmodified. Inverting it is a bug — one this
fork made and then fixed.

### Fonts

The menu font is `font_helvR08_te`, ISO10646-1 with **450 glyphs** — Unicode block elements at
U+2580 are outside a `_te` range. `menu.c` has **22 `u8g2_DrawStr`/`u8g2_GetStrWidth` call
sites and zero UTF-8 ones**, so multi-byte sequences would render as several wrong glyphs.

MiSTer's `.pf` fonts are 8 bytes per glyph, one bit per pixel, MSB left, **indexed from ASCII
`0x20`**. `Arcade_Major_Title_(IREM).pf` is 768 bytes = 96 glyphs covering `0x20`–`0x7F`, with
lowercase slots holding uppercase shapes. It carries a **solid 7×7 block at `0x7F`** — the
segment MiSTer's loading bar is drawn from. `0x7F` is a single byte and a legal XML character,
so it needs no UTF-8 handling. The hollow squares in MiSTer screenshots are **not** glyphs.

`Fonts_MiSTer` has **no licence**, and its files are traced from arcade and home-computer
character ROMs — so this repo ships [`pf2bdf.py`](../fpga/src/usb/pf2bdf.py) and no font.

---

## 5b. WiFi — open question

Today WiFi is an **ESP-01S** on pins 27/28 at a fixed **859372 bps**, with the UNAPI ROM
(`esp8266e.rom`) inside the BIOS pack talking to it through I/O ports `0x06`/`0x07`.

**Established:** FPGA-Companion ships `at_wifi.c`, a Hayes AT-command modem running over the
FPGA "port" interface (`sys_port_write`) — the `sysctrl` CMD 7 mechanism, for which this core
**already has plumbing**. A Pico W could therefore serve the network directly over SPI, with
credentials in the companion's `.ini` on SD, removing the module and freeing two pins.

**Not established:** whether `at_wifi.c` speaks enough of the ESP8266 AT dialect for the
bundled UNAPI ROM; whether the shield's Pico is a **W** variant (the stock `.uf2` is built
`PICO_BOARD=pico_w` with `ENABLE_WIFI`, but a plain Pico has no radio); and what the radio
costs the companion alongside USB host duty.

**Cannot be done in the OSD:** credential entry. The XML has no text-entry widget and CMD 4
carries one byte per id, so an SSID cannot be transported. Toggles, a reconnect button and a
fixed pick-list are expressible; configuration is not. It stays in the core's `W` menu.

MSXimus, the same author's Console 60K core, moved to an **ESP32-C6** with an optional
display instead — possibly the better answer regardless.

---

## 6. MSXnano internals

### Slot map

Slots **0 and 3 are expanded and full**; **1 and 2 are the free primaries**.

| Slot | Contents |
|---|---|
| 0-0 / 0-1 / 0-2 / 0-3 | BIOS / Kanji driver / WiFi ROM / logo |
| 3-0 / 3-1 / 3-2 / 3-3 | mapper / sub-ROM / SD (Nextor) / megaram + SCC |

The "Second SCC" option claims one of slots 1 and 2 — `scc2x_slot` is *"slot 1 if the megaram
is in slot 2 and vice versa"* — so it and any future SFG would compete for the same slot.

### The browser shows only 115 entries per directory

```asm
MAX_ENT  equ  115    ; array capacity (115*80 = 9200 bytes -> C300..E6F0)
```

A fixed array at `C300`–`E6F0`, 80 bytes per record, and the scan simply stops when full —
**with no indication that anything was truncated**. Raising the constant barely helps:
`PART_TBL` sits immediately above at `E800`, so even taking everything up to the system area
yields about 155. The record size is the constraint and `NAME_MAX` of 70 dominates it. The
listing is in raw FAT order with no sort, which makes streaming a viable fix. The cap is
**per directory**, so subdirectories are the workaround.

### Console emulation was removed upstream

v1.9 (`ce46ef9`, "MSX-only cleanup") deleted ColecoVision and SG-1000 entirely: `console_mode`
out of `top.v`, the console memory map out of `megaram.v`, **`sn76489.v` deleted** and dropped
from `build.tcl`, and the menu stripped of `.SG`/`.COL` detection, `COLECO.ROM` and its
strings. The v1.8 README still described them, which is how this fork briefly claimed support
it did not have.

Restoring it is a revert, and it is also the groundwork for the wider **Z80 + TMS9918 +
SN76489** family — Sega SC-3000, Sord M5, Memotech MTX. The **Spectravideo SV-328** is
cheapest of all, needing no new sound chip since it uses the AY-3-8910 already present.
**Master System / Game Gear are not cheap** — they need VDP **Mode 4**, a different tile and
palette architecture.

### Audio

The mixer output is **0-based unsigned** — silence is 0, not mid-scale — so a right shift
attenuates cleanly with no DC step or click. That is why the OSD volume is shift-only.

### Settings plumbing

`config1_ff` / `config2_ff` hold the settings and are driven by the `S` menu writing I/O
ports. Known bits: `config1_ff[3]` scanlines, `config1_ff[2]` second SCC+, `config2_ff[5]`
stereo, `config2_ff[4]` 16:9, `config_turbo_boot_ff` boot turbo (port `#45` bit 0, persisted).

Two settings have vestigial plumbing ready to revive: `pal_mode` exists in `v9958_top` but
follows VDP R9, and `config_keyboard[1:0]` is declared in `top.v` with its assignment
commented out. Autofire exists but is hardcoded to ~10 Hz.

---

## 6b. Unused capability already in the tree

Three things exist but are not connected, which is why they are cheap:

- **USB mouse.** `hid.v` exposes a mouse; `fpga_companion.v` has `//.mouse(hid_mouse),`
  commented out. The companion receives the data and the core discards it. What is missing is
  the MSX side — the mouse is read through the PSG joystick port.
- **PAL/NTSC.** `pal_mode` exists in `v9958_top` but follows VDP R9 rather than a setting.
- **Keyboard layout.** `config_keyboard[1:0]` is declared in `top.v` with its assignment
  commented out.

And one that exists but does not survive power-off: **cartridge SRAM** for ASCII8/ASCII16,
in the top 32 KB of the megaram, gated by port `#43`. Persisting it means reusing
`flash_rw.v`, whose `write_terminate` is declared `output` and never assigned
(`AUDIT_PRE_PORT_60K.md`), so PAGE PROGRAM always writes 256 bytes — harmless today, not
harmless once saves depend on it.

**Absent entirely:** `.cas` cassette support. The boot menu matches only `ROM` and `DSK`.
A reusable implementation exists in `MSX1_MiSTer/rtl/tape.sv` (molekula, GPL v2+): it streams
the CAS from RAM and generates the cassette bitstream, so the real BIOS decodes it and
hook-bypassing loaders still work.

Also worth knowing that **OPL4 and V9990 do fit on a GW2AR-18** — `antxiko/mangOPL4` and
`herraa1/tnCartWonder` run them on a Tang Nano 20K. But those implement a *cartridge* for a
real MSX, not a whole machine, which is why there is room. It does not follow that they fit
alongside a complete MSX2+.

---

## 6c. What MSXimus does that this cannot

[MSXimus](https://github.com/Papipapito/MSXimus) is the same author's core for the Tang
Console **60K** (GW5AT-60), GPLv3. It carries **MoonSound/OPL4** (OPL3 plus 24-voice
wavetable), **MSX-Audio Y8950** with ADPCM-B and 256 KB sample RAM, and HRA!'s **V9968** — an
extended VDP with 16 sprites per line, 15-colour sprites and 256 KB of VRAM held in the
board's **DDR3**. None of that is reachable on a GW2AR-18 with no DDR3; the move to the 60K is
precisely why they exist there.

Plausibly backportable, if a utilisation figure ever justifies it: full **2 MB ASCII16**
megaROMs (a mapper/capacity matter — the 20K has 8 MB of SDRAM in package), the **audio
remaster** (DC blocking on the PSGs, per-chip balance, a soft-knee limiter), **master volume
via `OUT &H44,n` persisted to flash**, and CRT borders with exact integer scaling.

⚠️ That DC blocking is a caution against this fork's own volume implementation, which assumes
the mix is 0-based with silence at 0 and therefore shifts cleanly. If there is a DC component,
attenuating by shifting moves it and clicks. Verify before trusting it.

---

## 7. Upstream documentation errors

Recorded because two of them cost real time, and because they are a reason to verify
upstream's hardware claims against the tree rather than trusting them.

| Claim | Reality |
|---|---|
| `S2: UPDATE (BL616 ISP mode)` | S2 is for FPGA flashing; BOOT is a separate button |
| `USB-A ──── USB keyboard` in the connection diagram | The board has no USB-A |
| BOM: ESP-01S on pins 77 and 73 | Moved to 27/28 in v1.7.2 — and 77/73 are DB9 lines in this fork |
| README lists ColecoVision and SG-1000 | Removed in v1.9 |
| BIOS pack "not distributed here" | It ships in `bin/` and as a release asset |
| `SPI.md` tile-address description | Contradicted by `osd_u8g2.c`; trust the code |
