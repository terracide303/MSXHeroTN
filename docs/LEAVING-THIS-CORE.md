# Leaving this core

Switching the Tang Nano 20K to a different FPGA core — an Amiga, a C64 — from the SD card,
without a PC.

**The mechanism is not part of this project.** It lives in
[CoreSwitch](https://github.com/terracide303/CoreSwitch), because it is a MiSTle-family problem
rather than an MSX one, and because a spec that several cores implement should not be owned by
one of them.

**Neither side is built yet.**

## What MSXHeroTN has to do

Instantiate two modules and add one OSD entry. That is all, and deliberately so — the same three
steps apply to every MiSTle core regardless of what it emulates.

| | |
|---|---|
| `sdc_mcu.v` | answers the MCU's SD commands, giving the Pico block access to the card |
| the flash writer | lets the MCU write the boot image |
| an OSD entry | **Exit Core** |

**The Z80 is not involved**, and that is the point. An earlier draft had the boot menu read the
file, because it already parses FAT — but the Amiga core would then need the same thing in
68000, the C64 in 6502, and so on. The Pico is the one thing every MiSTle core has in common, so
the Pico does the reading.

That also sidesteps a problem here: the boot menu is within 251 bytes of filling its 16 KB page,
so adding file-reading code to it was going to mean deleting something first.

## Arbitration

The MCU becomes a second user of the SD card alongside Nextor, which is the case where mistakes
cost somebody their disk images rather than a setting.

For this operation it is avoidable: **leaving the core means the MSX is finished.** Hold it in
reset before the MCU touches the card and there is no second master. `sdc.c` also polls the busy
status and waits, so the firmware already expects to share.

From the user's side that is one menu entry and a blink.

## Already done

`/CORES` is hidden from the game browser — a root-level directory whose short name is exactly
`CORES` is skipped by the scan, so the core folder does not clutter a list of games. Root level
only, so a `CORES` folder nested elsewhere still browses normally.

## The risk, in one line

Whatever sits at flash address 0 is what boots — this chip has no DUAL BOOT to fall back on — so
a failed write means recovering with `openFPGALoader` over USB-C, with the Tang out of the
shield. Verify before erasing, always.
