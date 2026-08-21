# Known-good builds — never overwritten

Bitstreams **verified working on real hardware**, kept apart from `compiled/` so that a later
build cannot replace them. Nothing here is ever updated in place: a newer verified build gets
a new file and a new tag, and the older ones stay.

Newest first.

| Bitstream | Source | SHA-256 | Verified | Notes |
|---|---|---|---|---|
| `msxnano-mistle_tangnano20k_25f80b8.fs` | `25f80b8`, tag `known-good-25f80b8` | `4733604d83c59867…` | 2026-08-21 | **Settings persist.** `clock_54m` 54.306 MHz — a pass, but thin |
| `msxnano-mistle_tangnano20k_6389ac0.fs` | `6389ac0`, tag `known-good-6389ac0` | `ff56143548757357…` | 2026-08-21 | Settings lost at power-off. `clock_54m` 55.626 MHz |

## Going back to one

**Stay on `main` and flash the file from this folder. Do not check the tag out first.**

```sh
git checkout main
openFPGALoader -b tangnano20k -f compiled/known-good/msxnano-mistle_tangnano20k_25f80b8.fs
```

**Take the Tang out of the shield first.** With the shield attached the FTDI device enumerates
but JTAG fails with `ftdi_usb_reset failed (-6)`.

The BIOS pack at `0x200000` is independent of the core and unchanged, so it does not need
reflashing. The bitstream alone gets you a working machine.

### Why not to check the tag out

**In this repository a commit's `compiled/*.fs` is the build of an *earlier* commit.** The Mac
commits source; the PC builds it and commits the bitstream afterwards, so the two are always
one step out of phase.

Concretely: `compiled/msxnano-mistle_tangnano20k.fs` at tag `known-good-6389ac0` is the build
of `8e6a5e9`, not of `6389ac0`. Checking out a tag and flashing what you find in `compiled/`
gives you the wrong bitstream, with no error to tell you so.

This folder exists precisely so the fallbacks are not subject to that. Every file here is
pinned to a SHA-256 and is never rebuilt or replaced.

To find the bitstream belonging to a given source commit, look for the commit whose message
reads *"built from `<sha>`"*.

### Building from one of these points

```sh
git checkout known-good-25f80b8
```

That is the only reason to check a tag out.

## What was verified

**`25f80b8`** — everything below, plus settings surviving a power cycle: volume set to 50%,
saved, power pulled, and it came back at 50%.

**`6389ac0`** — boots to the file browser and runs games. DB9 joystick, all directions and both
fire buttons. `F12` overlay, centred. Volume, scanlines, aspect, stereo, second SCC+, Reset and
Cold Boot. English boot menu titled `MSXHero TN 1.0`.

## Ownership

`compiled/` is otherwise the build machine's to write. **This subfolder is the exception — it
is not to be overwritten, cleaned, or updated by a build.** Failed builds belong in
`compiled/failed/`.
