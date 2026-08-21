# Bill of Materials

Parts needed to build an **MSXHeroTN** — MSX2+ on a Tang Nano 20K carried by a
MiSTeryShield20k RPi Pico USB shield.

> The core runs on hardware. See the [main README](../README.md) for what does and does not
> work before buying anything on the strength of this list.

## Core

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 1 | 1 | **Sipeed Tang Nano 20K** (GW2AR-18) | The FPGA board. Developed against one silkscreened `3923`. |
| 2 | 1 | **MiSTeryShield20k RPi Pico USB** | Carries the RP2040, USB host, DB9 joystick port and MIDI sockets. This fork requires it. Open hardware from the [MiSTle](https://github.com/MiSTle-Dev) project — KiCad sources in [MiSTle-Dev/Boards](https://github.com/MiSTle-Dev/Boards/tree/main/misteryshield20k_rpipico), so you can have it fabricated yourself. |
| 3 | 1 | **Raspberry Pi Pico** | Seats on the shield and runs FPGA-Companion as the USB HID host. A Pico W works too. |
| 4 | 1 | **microSD card** | FAT16 or FAT32, for `.rom` and `.dsk` files. Any size; small is fine. |
| 5 | 1 | **USB-C cable** | Power and FPGA programming. |
| 6 | 1 | **micro-USB cable** | For flashing the Pico's firmware. |
| 7 | 1 | **HDMI cable** | Video and audio. |
| 8 | 1 | **USB keyboard** | Plugs into the **shield's** USB host port. |

Note that the Tang Nano 20K itself has **one USB-C connector and no USB-A**. The USB host
port belongs to the shield, not the Tang. Upstream's BOM and connection diagram both claim
otherwise; they are wrong.

Because the shield hosts the keyboard, no USB hub or OTG adapter is needed — that
arrangement is only forced on a bare Tang, where the single USB-C has to carry power and
the keyboard at once.

## Input _(optional)_

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 9 | 1 | **DB9 joystick** | Atari/MSX-style digital stick into the shield's DE9 port. Works — verified on hardware. |
| 10 | 1 | **USB gamepad** | XInput (Xbox-style) recommended. Works alongside the DB9 stick on the same MSX port. |
| 11 | 1 | **USB hub** | Only if you want two USB gamepads. Player 2 is the second XInput device enumerated. |

## WiFi

**Not part of 1.0.** Upstream wires an ESP-01S to pins 27 and 28; on this shield those are the
joystick's Fire 1 and Down lines, so upstream's wiring cannot be used here. Bringing WiFi back
another way is being worked on — see the `dev` branch.

## Enclosure

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 14 | 1 | **3D-printed case** | STLs in [`../case/`](../case), white PETG recommended. **Designed for a bare Tang Nano 20K and will not fit with the shield attached** — see [`../case/README.md`](../case/README.md). |
| 15 | — | Screws / standoffs | Depends on the case revision. |

## Notes

- No soldering for the base build: the shield, keyboard, SD and HDMI are all connectorised.
  Only the optional ESP-01S needs header wiring.
- **Nothing is flashed to the Tang's on-board BL616.** This fork drops that path — the
  companion firmware goes onto the Pico instead. Flashing steps are in the
  [main README](../README.md).
- `MSXnano_BOM.xlsx` in this directory is upstream's spreadsheet for a bare-Tang build and
  has not been updated for the shield.

## About the shield

The MiSTeryShield20k is part of the **[MiSTle](https://github.com/MiSTle-Dev)** project — the
same people behind [FPGA-Companion](https://github.com/MiSTle-Dev/FPGA-Companion) and the
MiSTeryNano, NanoMig, C64Nano and NanoMac cores. The board designs are published as KiCad
sources in [MiSTle-Dev/Boards](https://github.com/MiSTle-Dev/Boards), which holds several
variants:

| Variant | Notes |
|---|---|
| `misteryshield20k_rpipico` | the one this fork targets |
| `misteryshield20k_rpipico_dual_db9` | two joystick ports instead of one |
| `misteryshield20k` | the original, WiFi rather than an RP2040 |
| `misteryshield20k_lite` | no WiFi, and its absence cannot be auto-detected |
| `misteryshield20k_ds2_adapter` | PlayStation 2 controller adapter |

Note that FPGA-Companion's own README still links the shield to
`vossstef/tang_nano_20k_c64/board/…`, which now 404s — the board designs were moved into their
own repository.

Supporting the dual-DB9 variant is a roadmap item; this fork currently mixes its single DB9
into one MSX port, selectable between port 1 and port 2 from the overlay.

## Without the shield: a Pico on a breadboard

The shield is the tidy way to do this, but the parts it provides are not magic. FPGA-Companion
runs on a **bare Raspberry Pi Pico**, and its pinout is published, so a breadboard build is
possible: a Pico, a USB-A socket for the keyboard, and six wires to the Tang's `m0s` header.

From [FPGA-Companion's RP2040 notes](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/src/rp2040):

| Pico pin | Signal | Goes to |
|---|---|---|
| GP2 / GP3 | USB D+ / D− | the USB-A socket for the keyboard |
| GP16 | MISO | FPGA |
| GP17 | CSn | FPGA |
| GP18 | SCK | FPGA |
| GP19 | MOSI | FPGA |
| GP22 | IRQn | FPGA |
| GP4 / GP5 / GP6 | LEDs | optional — mouse, keyboard, joystick indicators |

GP0 is a serial debug output at 921600 baud, which is worth bringing out if you are wiring
this yourself.

**What you lose.** The DB9 joystick port on this core is wired to the *shield's* pins, so a
breadboard build has no joystick socket unless you replicate that too — six lines to FPGA
pins 25, 26, 27, 28, 29 and 30, active-low to ground with pull-ups. The MIDI sockets likewise.
A USB gamepad still works, because that comes through the Pico.

If you would rather have the board made properly, the shield is open hardware:
[MiSTle-Dev/Boards](https://github.com/MiSTle-Dev/Boards/tree/main/misteryshield20k_rpipico)
has the KiCad sources.
