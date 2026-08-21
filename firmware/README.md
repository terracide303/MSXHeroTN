# Pico firmware

`fpga_companion.uf2` — the firmware for the **Raspberry Pi Pico** on the shield. It runs the
USB keyboard and gamepads, and draws the `F12` overlay.

## Install it

Hold **BOOTSEL** on the Pico, plug it into a computer, and drag this file onto the `RPI-RP2`
drive that appears. The Pico reboots into it. That is the whole procedure — no toolchain, no
compiler.

Nothing is flashed to the Tang's on-board BL616. This core does not use that chip.

## Where it came from

This is **stock FPGA-Companion, unmodified** — byte-identical to the `fpga_companion.uf2` asset
from [FPGA-Companion v1.4.21](https://github.com/MiSTle-Dev/FPGA-Companion/releases/tag/v1.4.21):

```
SHA-256  0e07fb99bd94b66c5e6a693c...
```

It is kept here because **upstream does not publish a Pico binary in every release** — the
latest ships BL616 images but no `.uf2` at all — so following the link does not reliably get
you one. This is a known-good build that works with this core.

To build it yourself, or to read what it does, the source is at
[MiSTle-Dev/FPGA-Companion/src/rp2040](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/src/rp2040).
That directory also documents the Pico's pinout, which is what you need to wire one onto a
breadboard instead of using the shield — see [docs/BOM.md](../docs/BOM.md).

## Licence

FPGA-Companion is **Apache-2.0**, which permits redistribution. Copyright stays with its
authors; this is their binary, unchanged.
