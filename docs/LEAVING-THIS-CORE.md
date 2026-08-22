# Leaving this core

Switching the Tang Nano 20K to a different FPGA core — an Amiga, a C64 — from the SD card,
without a PC.

**The mechanism is not part of this project.** It lives in
[CoreSwitch](https://github.com/terracide303/CoreSwitch), because it is a MiSTle-family problem
rather than an MSX one, and because a spec that several cores implement should not be owned by
one of them.

**Neither side is built yet.**

## What MSXHeroTN has to do

Almost nothing, which is the point of the split. To be escapable, a core copies one fixed file
to flash and reboots:

1. Read `/CORES/LOADER.BIN` from the SD card
2. Verify it — `A5 C3` preamble, IDCODE `08 1B` for the GW2AR-18
3. Write it to flash address 0
4. Reconfigure

CoreSwitch then comes up and handles everything else: listing cores, reading manifests,
validating, writing, rebooting. This core never sees a list and never parses a manifest.

## How it is reached

`F12` → **Select Core**.

The overlay cannot act directly. It only sends config values to the core, and the work needs the
SD card and FAT parsing, which live in the boot menu — not running during a game. So the entry
sets a spare config bit and resets; the menu sees the bit at start-up and does the flashing
before drawing anything. **`config2` bit 3 is free**, where Compatible Mode lived until v1.9
removed it.

From the user's side that is one menu entry and a blink.

## Already done

`/CORES` is hidden from the game browser — a root-level directory whose short name is exactly
`CORES` is skipped by the scan, so the core folder does not clutter a list of games. Root level
only, so a `CORES` folder nested elsewhere still browses normally.

## The risk, in one line

Whatever sits at flash address 0 is what boots — this chip has no DUAL BOOT to fall back on — so
a failed write means recovering with `openFPGALoader` over USB-C, with the Tang out of the
shield. Verify before erasing, always.
