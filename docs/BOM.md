# Bill of Materials

Parts needed to build an **MSXnano-MiSTle** — MSX2+ on a Tang Nano 20K carried by a
MiSTeryShield20k RPi Pico USB shield.

> This fork is not working yet. See the [main README](../README.md) before buying
> anything on the strength of this list.

## Core

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 1 | 1 | **Sipeed Tang Nano 20K** (GW2AR-18) | The FPGA board. Developed against one silkscreened `3923`. |
| 2 | 1 | **MiSTeryShield20k RPi Pico USB** | Carries the RP2040, USB host, DB9 joystick port and MIDI sockets. This fork requires it. |
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
| 9 | 1 | **DB9 joystick** | Atari/MSX-style digital stick into the shield's DE9 port. Support is **implemented but untested**. |
| 10 | 1 | **USB gamepad** | XInput (Xbox-style) recommended. Works alongside the DB9 stick on the same MSX port. |
| 11 | 1 | **USB hub** | Only if you want two USB gamepads. Player 2 is the second XInput device enumerated. |

## WiFi _(optional — MSX UNAPI)_

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 12 | 1 | **ESP-01S** (ESP8266) | Wired to the GPIO header: **ESP TX  pin 28, ESP RX  pin 27**, VCC  3.3V, GND  GND. Flash with ducasp ESPFW1.4 (OCM build). |
| 13 | — | Jumper wires / header | To reach the Tang's header. |

The UNAPI ROM is already inside the BIOS pack, so there is no separate ROM to flash.

> **Pin correction.** Upstream's BOM says the ESP-01S goes on pins 77 and 73. That was true
> before MSXnano v1.7.2 moved the UART to pins 27/28, and it is doubly wrong here: pins 77
> and 73 are the DB9 Up and Fire-1 lines in this fork. Wiring an ESP-01S to them would fight
> the joystick port. Use 28 and 27.

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
