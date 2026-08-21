# Known-good build — do not overwrite

This folder holds the last bitstream **verified working on real hardware**, kept apart from
`compiled/` so that a later build cannot replace it. Nothing here is ever updated in place: a
newer known-good build gets a new file and a new tag, and the old one stays.

| | |
|---|---|
| Source commit | `6389ac0` — tagged **`known-good-6389ac0`** |
| Bitstream | `msxnano-mistle_tangnano20k_6389ac0.fs` |
| SHA-256 | `ff56143548757357…` (matches `compiled/msxnano-mistle_tangnano20k.fs` as of this commit) |
| Verified | 2026-08-21, Tang Nano 20K in a MiSTeryShield20k |
| Timing | `clock_54m` 55.626 MHz against 54.000, zero negative slack on all six domains, CLS 9054/10368 (87%) |

## What was confirmed by hand

Boots to the file browser and runs games. DB9 joystick, all directions and both fire buttons.
F12 OSD, centred. Volume, scanlines, aspect, stereo, second SCC+, Reset and Cold Boot. English
boot menu titled `MSXHero TN 1.0`.

Not present in this build: settings persistence. Volume and DB9 port are lost at power-off.

## Going back to it

Flashing the bitstream is enough to get a working machine — the source only matters if you
want to build from that point again.

```sh
openFPGALoader -b tangnano20k -f compiled/known-good/msxnano-mistle_tangnano20k_6389ac0.fs
```

**Take the Tang out of the shield first.** With the shield attached the FTDI device enumerates
but JTAG fails with `ftdi_usb_reset failed (-6)`.

The BIOS pack at `0x200000` is independent of the core and has not changed, so it does not
need reflashing.

To build from this point:

```sh
git checkout known-good-6389ac0
```

## Ownership

`compiled/` is otherwise the build machine's to write. **This subfolder is the exception —
it is not to be overwritten, cleaned, or updated by a build.** Failed builds belong in
`compiled/failed/`.
