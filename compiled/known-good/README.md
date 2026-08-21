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

**Stay on `main` and flash the file in this folder. Do not check the tag out first.**

```sh
git checkout main
openFPGALoader -b tangnano20k -f compiled/known-good/msxnano-mistle_tangnano20k_6389ac0.fs
```

**Take the Tang out of the shield first.** With the shield attached the FTDI device enumerates
but JTAG fails with `ftdi_usb_reset failed (-6)`.

The BIOS pack at `0x200000` is independent of the core and has not changed, so it does not
need reflashing. Flashing the bitstream alone gets you a working machine.

### Why not to check the tag out

**In this repository a commit's `compiled/*.fs` is the build of an *earlier* commit.** The Mac
commits source; the PC builds it and commits the bitstream afterwards. So the two are always
one step out of phase.

Concretely: `compiled/msxnano-mistle_tangnano20k.fs` at tag `known-good-6389ac0` is the build
of `8e6a5e9`, not of `6389ac0`. The build of `6389ac0` arrived later, in `ae7926c`. Checking
out the tag and flashing what you find in `compiled/` gives you the wrong bitstream, with no
error to tell you so.

This folder exists precisely so that the fallback is not subject to that. The file here is
pinned to a SHA-256 and is never rebuilt or replaced.

To find which bitstream belongs to a given source commit, look for the commit whose message
reads *"built from `<sha>`"*.

### Building from this point

```sh
git checkout known-good-6389ac0
```

That is the only reason to check the tag out.

## Ownership

`compiled/` is otherwise the build machine's to write. **This subfolder is the exception —
it is not to be overwritten, cleaned, or updated by a build.** Failed builds belong in
`compiled/failed/`.
