![MSXHeroTN](docs/img/banner.png)

# MSXHeroTN 1.1

**An MSX2+ home computer, in an FPGA, on a Tang Nano 20K.**

It boots to its own file browser, runs your ROMs off an SD card, takes a real joystick, and
puts everything on HDMI. A USB keyboard plugs straight into the shield. Press `F12` at any
time — in the browser or mid-game — for settings.

**Everything you need is in this repository**: the FPGA bitstream in [`compiled/`](compiled/),
the MSX BIOS pack in [`bin/`](bin/), and the Raspberry Pi Pico firmware in
[`firmware/`](firmware/). No toolchain, no compiler, no build step — flash three files and fill
an SD card.

It is a fork of [MSXnano](https://github.com/Papipapito/MSXnano), retargeted to run on the
**MiSTeryShield20k RPi Pico USB** — an open-hardware shield from the
[MiSTle](https://github.com/MiSTle-Dev) project — so that the shield's own hardware is wired to
something instead of sitting inert.

---

## Release 1.1

**What the machine does.** Everything here has been confirmed by hand on a real board — not by
reading the code, and not merely by compiling.

| | |
|---|---|
| Boots, browses the SD card, runs games | yes |
| DB9 joystick | yes — directions and fire. See below on second buttons |
| USB keyboard and gamepad | yes, through the shield |
| HDMI video and audio | yes |
| `F12` settings overlay | yes |
| Turbo — 5.37 MHz, the real Panasonic WSX speed | yes |
| Scanlines, aspect, stereo, second SCC+, volume | yes |
| Reset and Cold Boot from the overlay | yes |
| Remembering your settings | yes — kept in the FPGA's own flash |

### What changed in 1.1

Everything above already worked in 1.0. This release is about the **file browser** only, and
the core itself is unchanged — so upgrading from 1.0 **only needs the BIOS pack reflashed**,
not the FPGA.

- **The listing is sorted.** Alphabetically, ignoring capitals, folders first. It never was
  before — entries appeared in raw filesystem order, which is the order they happened to be
  written, so a card looked shuffled.
- **Housekeeping files are hidden.** `.Trashes`, `.fseventsd`, `._`-files and
  `System Volume Information` no longer appear. Every card formatted on a Mac or PC carries
  them, and they were taking up slots against the file limit.
- **Left leaves a folder.** Left pages back through the list, and once there is no page left to
  go back to, it exits the folder — so a one-button joystick can get out. `BACKSPACE` still
  works too.
- **The footer says what the keys do.** Paging and going back were never on screen at all, which
  is a poor way to learn that they exist.
- **Dead keys removed.** `S`, `W`, `U` and `F` are gone. `S` saved settings, which the `F12`
  overlay does now; the other three needed WiFi hardware this fork does not have, so they were
  live keys leading nowhere.

### Known limitations

Small things, written down rather than hidden.

**The overlay shows defaults after a power cycle**, even though the machine is using your
saved settings. Touch an entry and it catches up. The core has no way to tell the overlay what
it loaded, so this is a display quirk rather than a fault.

**The browser lists only the first 115 files in a directory.** Anything past that is invisible
with no warning. Use folders in the meantime.

**Turbo is applied by resetting into it.** Changing CPU speed while the machine is running
hangs it, so the overlay resets instead.

---

## What it looks like

The browser starts before the OS, so you pick a game before there is an MSX to run it.

![The settings overlay on top of the file browser](docs/img/osd-root.jpg)

`F12` brings the overlay up over whatever is running.

![System settings](docs/img/osd-system.jpg)
![Audio settings](docs/img/osd-audio.jpg)
![Video settings](docs/img/osd-video.jpg)
![Input settings](docs/img/osd-input.jpg)

---

## Why this fork exists

[MSXnano](https://github.com/Papipapito/MSXnano), which this forks, is a fine core and the
reason this one exists at all. It runs on a bare Tang Nano 20K and uses a chip on the
board itself as its USB host. That works, but it constrains the machine in ways that are easy
to miss until you are living with one.

### The original MSXnano has no settings overlay. This one does.

That is the headline difference, and the one you notice every day.

The helper chip that handles the keyboard is perfectly capable of drawing a settings menu — it
runs the same firmware here, and it offers one. The original simply never connects that menu to
the picture, so it is drawn and then thrown away, with nothing listening for it.

So settings live somewhere else: a small screen inside the **boot browser**, drawn by the MSX
itself.

That is the part that bites. A screen drawn by the MSX can only exist when the MSX is not busy
being an MSX — it needs the video chip, and once a game has started, the game owns the video
chip. The settings screen and your game cannot both be on screen, ever.

**All of the following are fixed here.** Each is how the original behaves; each one works on
this fork, because the overlay is drawn by the FPGA rather than by the MSX.

- **You cannot change anything while playing.** Want scanlines off, or stereo on, or the second
  SCC+ enabled? Reset back to the browser, change it, reload the game. Every time.
- **There is no volume control at all.** Not quietly, not anywhere — it simply is not a setting.
  Your only volume knob is the television.
- **Turbo is a stolen keyboard key.** `F11` is intercepted before the MSX sees it, so the core
  takes a key away from the machine to work around having no menu.
- **There is no reset or cold boot in software.** You reach for the button on the board.

The fix is to draw the overlay in the FPGA itself, between the video chip and the HDMI encoder.
It is painted onto the picture on its way out to the screen, so it never asks the MSX for
permission and never needs the game to stop.

That is why `F12` works anywhere — mid-game, mid-load, in the browser — with turbo, volume,
video and audio settings, reset and cold boot all reachable without losing what you are doing.
And `F11` goes back to being an ordinary key that belongs to the MSX.

### What a "shield" actually is

If the word is new to you: a shield is a carrier board that other boards plug into. It has no
processor of its own and runs no software. It is a socket, some connectors and the wiring
between them.

![The MiSTeryShield20k with a Raspberry Pi Pico and a Tang Nano 20K plugged into it](docs/img/shield.png)

That is the whole machine. **Two small, cheap boards sit in it** — the Raspberry Pi Pico on the
left and the Tang Nano 20K on the right — and the shield gives them sockets a bare board does
not have: USB-A for the keyboard, a DE9 for the joystick, MIDI. Both boards lift straight out.

The Tang Nano 20K is the computer: the FPGA on it *becomes* the MSX. The Pico handles USB, so
the keyboard has somewhere to plug in and the Tang's own USB-C is left doing nothing but power.
The chip on the Tang that would otherwise do that job is left untouched — this fork never
flashes it.

The joystick and MIDI sockets you can see are wired to the FPGA, but the original core never
assigns any pins to them, so on this shield they sit dead. Wiring them up is what this fork is
for.

## What you need

| Part | Notes |
|---|---|
| **Sipeed Tang Nano 20K** | the FPGA board |
| **MiSTeryShield20k RPi Pico USB** | required — it carries the USB port and the joystick socket. Open hardware from the [MiSTle](https://github.com/MiSTle-Dev) project: [KiCad sources](https://github.com/MiSTle-Dev/Boards/tree/main/misteryshield20k_rpipico) |
| **Raspberry Pi Pico** | sits on the shield and handles the keyboard. Firmware is [included here](firmware/) |
| **microSD card** | FAT16 or FAT32, any size |
| **USB keyboard** | plugs into the shield |
| **A joystick** | optional — either a DB9 stick into the shield, or a USB controller |

Plus the usual cables — USB-C for power and HDMI for the display.

Nothing else needs downloading. The bitstream, the BIOS pack and the Pico firmware are all in
this repository, ready to flash.

The full list, with the reasoning and the places the original project's own parts list is
wrong, is in [docs/BOM.md](docs/BOM.md). It also covers building this **without the shield**, on a
breadboard with a bare Pico, and what you give up by doing that.

### Controllers

A **DB9 joystick** — the Atari/MSX kind — plugs straight into the shield and works. You choose
which MSX port it answers on from the overlay.

**On second buttons.** The shield's DE9 follows the Atari/Amiga convention, with button 2 on
pin 9 — it was designed for Atari ST and Amiga cores. MSX joysticks put their second button on
pin 7 instead, which the shield uses for +5V, so an MSX-pinout stick can deliver directions and
fire 1 but not fire 2. In practice this costs little, since most MSX sticks only have one
button. Fire 2 does work on an Atari, Amiga, Commodore or Mega Drive controller, and on any USB
gamepad, which does not use this connector.

If you have a two-button *MSX* stick, it is worth not pressing button 2: it switches pin 7 to
ground, and the shield holds pin 7 at +5V.

**USB controllers** go through the shield's USB port. XInput devices work; anything else
mostly does not:

| Controller | |
|---|---|
| Xbox 360, wired | works |
| Xbox 360-compatible clones (XInput) | works |
| Xbox One in XInput mode | works |
| Lenovo X01 with its USB dongle | works |
| Xbox Series X/S | no — different protocol |
| PlayStation 4 / 5 | no |

Player 1 is the first XInput device enumerated, player 2 the second, which needs a hub. The
DB9 stick and a USB pad are mixed onto the same MSX port, so either can drive a game — **and
either can drive the file browser**, so you never need the keyboard to pick and start something.

Note that the Tang Nano 20K has **no USB-A socket**. The keyboard plugs into the *shield*. On
a bare Tang you would need a powered hub and an OTG adapter; the shield is what removes that.

---

## Getting it running

### 1. Flash the FPGA

> **Take the Tang out of the shield first.** With the shield attached, programming fails with
> `ftdi_usb_reset failed (-6)`. Out of the shield it works every time.

[`openFPGALoader`](https://github.com/trabucayre/openFPGALoader) is what we use, on macOS:

```sh
# the core
openFPGALoader -b tangnano20k -f compiled/msxnano-mistle_tangnano20k.fs

# the BIOS pack — only needed once
openFPGALoader -b tangnano20k --external-flash -o 0x200000 --file-type raw bin/goauld_rom_int.bin
```

**[`compiled/msxnano-mistle_tangnano20k.fs`](compiled/) is the file to flash** — the 1.0
release, verified on hardware. It is the only bitstream in that folder, so there is nothing to
choose between, and you do not need an FPGA toolchain unless you want to change something.

The BIOS pack is **[`bin/goauld_rom_int.bin`](bin/)** — a single 512 KB image holding the MSX2+
BIOS, the sub-ROM, the logo/FM menu, Nextor 2.1.4 and the boot browser. It only changes if the
boot menu changes, so flashing it once is normally enough.

**On Windows**, openFPGALoader officially supports the platform and ships Windows builds, but
getting it to see the board is often the sticking point: Windows binds its own FTDI driver to
the Tang's programmer, and openFPGALoader needs a WinUSB-class driver instead — usually swapped
with [Zadig](https://zadig.akeo.ie/). That is the common cause rather than something we have
confirmed here. **Gowin Programmer**, the vendor tool, works natively on Windows and is what
the original project's instructions assume; use `exFlash C Bin Erase, Program thru GAO-Bridge`
for the BIOS pack.

### 2. Flash the Pico

Hold BOOTSEL, plug it into a computer, and drag **[`firmware/fpga_companion.uf2`](firmware/)**
onto the `RPI-RP2` drive that appears. That is the whole procedure.

It is stock [FPGA-Companion](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/src/rp2040),
unmodified, kept here because FPGA-Companion does not publish a Pico binary in every release —
the latest ships none at all. Provenance and licence are in
[`firmware/README.md`](firmware/README.md).

> Do **not** flash companion firmware onto the Tang's own BL616 chip. It replaces the
> programmer, and afterwards you cannot talk to the board at all. This fork does not use that
> chip for anything.

### 3. Fill the SD card

Copy `.rom` and `.dsk` files onto it and put it in the Tang.

**Use folders.** The browser shows only the **first 115 entries of any one directory**, and
anything past that is silently invisible — no warning, no error, the files simply are not
listed. This catches people out with a big collection dumped in the root.

The fix is easy and it is worth doing before you fill the card: split the collection
alphabetically, `A-E`, `F-J`, `K-O`, `P-U`, `V-Z`, and no folder comes close to the limit.
Subdirectories nest as deep as you like, so by publisher or by year works just as well.

Power up, and you should be looking at the browser.

---

## Using it

| Extension | Loaded as |
|---|---|
| `.rom` | cartridge, with the mapper detected automatically |
| `.dsk` | disk image, through Nextor |

Only those two. A `.mx2` file is byte-identical to a `.rom` but stays **invisible until you
rename it**, because the browser matches the three extension letters literally.

**In the browser:** up and down move, **left and right page**, RETURN launches, and `BACKSPACE`
or **left at the top of the list** leaves a folder. `R`/`D`/`A` filter by type, TAB switches
partition, `H` opens help, and ESC boots straight to MSX-DOS.

The listing is sorted alphabetically with folders first, and files the operating system hides —
`.Trashes` and friends — are not shown.

**`/` searches by name** — type part of a filename and it jumps there. Useful well before you
hit the file limit.

**The joystick works here too.** Up and down move, left and right page, **fire 1 launches** and
**fire 2 goes back**, with auto-repeat if you hold a direction. So you can pick and start a game
without reaching for the keyboard at all — a DB9 stick or a USB pad, either one.

**`F12`** opens the settings overlay, in the browser or in a game.

A cartridge is loaded into slot 3-3. This is the layout the MSX sees:

![MSX slot map](docs/img/slot-map.png)

---

## If something goes wrong

Every release on this branch is tagged and carries the matching bitstream, so going back to an
earlier one is a checkout and a flash:

```sh
git checkout msxherotn-1.0
openFPGALoader -b tangnano20k -f compiled/msxnano-mistle_tangnano20k.fs
```

The BIOS pack does not need reflashing — it is independent of the core and unchanged.

`main` only ever advances to a build that has been confirmed working on a real board, so
whatever is on it should not need reverting in the first place.

---

## Branches

**`main` is the one that works**, and it is currently **1.0**. It only moves when a build has
been confirmed running on a real board — not merely when it compiles, and not merely when it
meets timing.

**`dev`** is where the work happens: half-finished features, builds that failed, the roadmap,
and the notes that go with all of it. If you want a machine rather than a project, stay on
`main`.

---

## Under the hood

The engineering detail lives in `docs/`, and it is written to be read rather than skimmed:

- **[docs/FINDINGS.md](docs/FINDINGS.md)** — everything established about the hardware, with
  the evidence for each claim: the shield's wiring, the Tang's board revisions, the companion's
  SPI protocol, and a table of errors found in the original project's documentation.
- **[docs/UTILISATION.md](docs/UTILISATION.md)** — resource and timing figures for every build,
  including the failures and what each one taught.
- **[docs/BOM.md](docs/BOM.md)** — the parts list.

Building it yourself needs **Gowin EDA**, which has no macOS version. If you are curious how
full the chip is, the short answer is 88%, and that has shaped most of the decisions here.

---

## What came from the original

The Z80, the V9958 video chip with HDMI output, dual PSG, SCC and SCC+, OPLL, the SD card with
Nextor 2.1.4 and the file browser are all [MSXnano](https://github.com/Papipapito/MSXnano)'s,
unchanged. This fork changes how the machine is wired up and how you talk to it, not what it
is.

---

## Credits and licence

**GPLv3**, inherited from MSXnano. Fork maintained by
[terracide303](https://github.com/terracide303).

Development on this fork is done with AI assistance — **Claude** (Anthropic), via
[Claude Code](https://claude.com/claude-code). The retargeting, the RTL changes and this
documentation were written with Claude's help and reviewed before committing; those commits
carry a `Co-Authored-By: Claude` trailer, so `git log` shows exactly which ones.

- [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano) — the core this forks
- [jabadiagm/MSXgoauldSD_tn20k](https://github.com/jabadiagm/MSXgoauldSD_tn20k) — MSXnano's own basis
- [MiSTle-Dev/FPGA-Companion](https://github.com/MiSTle-Dev/FPGA-Companion) — the Pico firmware
- [MiSTle-Dev/Boards](https://github.com/MiSTle-Dev/Boards) — the shield itself, as open KiCad
  hardware. This fork exists to make its connectors work
- [MiSTle-Dev/MiSTeryNano](https://github.com/MiSTle-Dev/MiSTeryNano) — where the shield's
  joystick pin assignment was read from, after getting it wrong twice
