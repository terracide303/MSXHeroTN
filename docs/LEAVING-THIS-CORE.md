# Leaving this core

Switching the Tang Nano 20K to a different FPGA core — an Amiga, a C64 — from the SD card,
without a PC.

**The mechanism is not part of this project.** It lives in
[CoreSwitch](https://github.com/terracide303/CoreSwitch), because it is a MiSTle-family problem
rather than an MSX one, and because a spec that several cores implement should not be owned by
one of them.

**Neither side is built yet.**

## What MSXHeroTN has to do

One block and one menu entry:

| | |
|---|---|
| A flash-write block | accepts bytes over SPI from the Pico, writes them to the boot image |
| One line of menu XML | **Exit Core** |

**No SD access is needed**, which is the part worth noticing. The Pico streams the loader's
bitstream from its own flash, so this core never opens a file, never parses FAT, and never
competes with Nextor for the card. The Z80 is not involved either.

That keeps the risky things out of it entirely. The worst this block can do is write a bad boot
image, which is recoverable over USB-C; it cannot touch your disk images.

CoreSwitch then comes up and does everything else.

## Settings on the SD card — separate, and wanted anyway

Independently of core switching, this core should move its settings from FPGA flash to the SD
card, the way other MiSTle cores do. That *does* need SD access for the Pico, and it *does* mean
sharing the card with Nextor, so it is its own piece of work with its own risks.

It would also fix a known wart: settings currently load from flash, but the overlay still shows
its defaults afterwards, because the core has no way to tell the overlay what it restored. If
the Pico owns the settings file, that inconsistency disappears.

## Already done

`/CORES` is hidden from the game browser — a root-level directory whose short name is exactly
`CORES` is skipped by the scan, so the core folder does not clutter a list of games. Root level
only, so a `CORES` folder nested elsewhere still browses normally.

## The risk, in one line

Whatever sits at flash address 0 is what boots — this chip has no DUAL BOOT to fall back on — so
a failed write means recovering with `openFPGALoader` over USB-C, with the Tang out of the
shield. Verify before erasing, always.
