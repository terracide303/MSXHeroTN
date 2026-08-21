![MSXHeroTN](docs/img/banner.png)

# MSXHeroTN 1.0

**An MSX2+ home computer, in an FPGA, on a Tang Nano 20K.**

It boots to its own file browser, runs your ROMs off an SD card, takes a real joystick, and
puts everything on HDMI. A USB keyboard plugs straight into the shield. Press `F12` at any
time — in the browser or mid-game — for settings.

**Both binaries you need are in this repository**: the FPGA bitstream in
[`compiled/`](compiled/) and the Raspberry Pi Pico firmware in [`firmware/`](firmware/). No
toolchain, no compiler, no build step — copy two files onto two chips and fill an SD card.

This is a fork of [Papipapito/MSXnano](https://github.com/Papipapito/MSXnano), retargeted to
run on the **MiSTeryShield20k RPi Pico USB** — an open-hardware shield from the
[MiSTle](https://github.com/MiSTle-Dev) project — so that the shield's own hardware is wired
to something instead of sitting inert.

---

## Release 1.0

The first finished release. Everything in this table has been confirmed by hand on a real
board — not by reading the code, and not merely by compiling.

| | |
|---|---|
| Boots, browses the SD card, runs games | yes |
| DB9 joystick | yes — all directions, both fire buttons |
| USB keyboard and gamepad | yes, through the shield |
| HDMI video and audio | yes |
| `F12` settings overlay | yes |
| Turbo — 5.37 MHz, the real Panasonic WSX speed | yes |
| Scanlines, aspect, stereo, second SCC+, volume | yes |
| Reset and Cold Boot from the overlay | yes |
| Remembering your settings | yes — kept in the FPGA's own flash |

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

Nothing else needs downloading. The bitstream and the Pico firmware are both in this
repository, ready to flash.

The full list, with the reasoning and the places upstream's own BOM is wrong, is in
[docs/BOM.md](docs/BOM.md). It also covers building this **without the shield**, on a
breadboard with a bare Pico, and what you give up by doing that.

### Controllers

A **DB9 joystick** — the Atari/MSX kind — plugs straight into the shield and works, including
both fire buttons. You choose which MSX port it answers on from the overlay.

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
DB9 stick and a USB pad are mixed onto the same MSX port, so either can drive a game.

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
openFPGALoader -b tangnano20k --external-flash -o 0x200000 --file-type raw goauld_rom_int.bin
```

**[`compiled/msxnano-mistle_tangnano20k.fs`](compiled/) is the file to flash** — the 1.0
release, verified on hardware. It is the only bitstream in that folder, so there is nothing to
choose between, and you do not need an FPGA toolchain unless you want to change something.

**On Windows**, openFPGALoader officially supports the platform and ships Windows builds, but
getting it to see the board is often the sticking point: Windows binds its own FTDI driver to
the Tang's programmer, and openFPGALoader needs a WinUSB-class driver instead — usually swapped
with [Zadig](https://zadig.akeo.ie/). That is the common cause rather than something we have
confirmed here. **Gowin Programmer**, the vendor tool, works natively on Windows and is what
upstream's instructions assume; use `exFlash C Bin Erase, Program thru GAO-Bridge` for the BIOS
pack.

### 2. Flash the Pico

Hold BOOTSEL, plug it into a computer, and drag **[`firmware/fpga_companion.uf2`](firmware/)**
onto the `RPI-RP2` drive that appears. That is the whole procedure.

It is stock [FPGA-Companion](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/src/rp2040),
unmodified, kept here because upstream does not publish a Pico binary in every release — the
latest ships none at all. Provenance and licence are in
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

**In the browser:** arrows and RETURN navigate and launch, BS goes back, `R`/`D`/`A` filter by
type, TAB switches partition, `H` opens help, and ESC boots straight to MSX-DOS.

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
  SPI protocol, and a table of upstream's documentation errors.
- **[docs/UTILISATION.md](docs/UTILISATION.md)** — resource and timing figures for every build,
  including the failures and what each one taught.
- **[docs/BOM.md](docs/BOM.md)** — the parts list.

Building it yourself needs **Gowin EDA**, which has no macOS version. If you are curious how
full the chip is, the short answer is 88%, and that has shaped most of the decisions here.

---

## What came from upstream

The Z80, the V9958 video chip with HDMI output, dual PSG, SCC and SCC+, OPLL, the SD card with
Nextor 2.1.4 and the file browser are all MSXnano's, unchanged.

---

## Credits and licence

**GPLv3**, inherited from upstream. Fork maintained by
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
