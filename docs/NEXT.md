# What we are doing next

Ordered by cost, not by appeal. The cheap items are genuinely cheap and the expensive ones are
genuinely expensive, and that gap is wider on this project than on most — see the note at the
bottom.

Full reasoning for every item is in [ROADMAP.md](ROADMAP.md); this file is the running order.

---

## Group A — boot menu only. No FPGA build.

**This is the cheap loop and it is worth exhausting before touching any RTL.** The boot menu is
Z80 assembly. It assembles to `fm_logo_menu.bin`, which occupies 16 KB at offset `0x6C000`
inside the BIOS pack, so a change means: assemble, splice, flash the pack at `0x200000`. One
`openFPGALoader` command.

No Gowin, no PC, no synthesis, **no timing risk** — the three things that have cost this project
the most time. It all happens on the Mac, and the toolchain is documented in
[`../fpga/src/msxnano_menu/BUILDING.md`](../fpga/src/msxnano_menu/BUILDING.md). You do not even
need the copyrighted BIOS dumps: the splice patches a pack you already have.

### A1. Drive the browser with a joystick

Read PSG register 14 and map the directions onto the keys the browser already handles, fire
onto RETURN. The DB9 stick and a USB pad are mixed onto the same PSG lines in the core, so both
work from one implementation.

Ordinary MSX programming, immediately useful every time you change game, and a mistake costs a
reflash rather than a build cycle. **Start here.**

### A2. Remove `S` from the menu

`S` opens a reduced on-MSX settings screen. Its only remaining job was saving to flash, and the
F12 overlay does that now — so it is redundant as of 1.0.

Two `cp #53` handlers at lines 451 and 2054, plus the settings screen itself. Note the status
bar is width-constrained: `"R/D/A=Filter ESC=Boot S=Save F12=Setup TAB=Part H=Help  "` is padded
to a fixed width and must stay that width when `S=Save` comes out.

Worth doing before A3, because deleting the settings screen frees Z80 space that A3 needs.

### A3. Remove the 115-file limit

The browser silently lists only the first 115 entries of any directory — no warning, they simply
are not there. The listing lives in a fixed array in MSX RAM, 80 bytes per record:

```asm
MAX_ENT  equ  115    ; 115*80 = 9200 bytes -> C300..E6F0
```

Fixing it means paging the listing rather than holding all of it, which is more involved than A1
or A2 but still Z80-only. The space freed by A2 helps.

---

## Group B — small RTL. Needs a PC build, so timing is a real risk.

Each of these adds a leg to the `cpu_din` read mux, which is the structure that governs timing
here. Do them **one at a time**, so a timing regression has one suspect.

### B1. MIDI ports

Two registers and a 31250-baud UART on pins 71 and 72, which are free. The FM chip is *not* part
of this — that goes to the ECP5 (C2).

**Answer this in openMSX before writing any Verilog:** does the SFG BIOS probe the OPM during
initialisation and refuse to install when the reads look wrong? If it does, the stubbed FM chip
has to be convincing enough to pass that probe. The test costs nothing and decides whether the
cheap half is worth building at all.

### B2. WiFi back, via the shield's J3 header

`uart_lite` and `wifi_lite` were deleted in `70de6ae`, not rewritten, so this is close to a
revert plus two `IO_LOC` lines against code that already worked. Pins 31, 49, 73, 74, 75 and 77
are all free.

**Check first, on the actual board:** does J3 carry 3V3 and ground? If it is signal-only the
module needs power from elsewhere — four jumper wires instead of two.

Also worth confirming whether the Pico on the shield is a **Pico W**. The photo in the README
suggests it is, which would open a second route that needs no module at all.

### B3. USB mouse

The roadmap calls this small because the Pico already decodes mice and the line in
`fpga_companion.v` is only commented out. **Verify that before believing it** — the missing
piece is likely the MSX-side mouse protocol on the joystick port, which is more than
uncommenting a line.

---

## Group C — prove on the ECP5 first

The ECP5 build has headroom; this one is at 88% CLS with `clock_54m` closing by 0.3 MHz. Both
machines share the F12 overlay, so anything proven there ports back.

### C1. Settings on the SD card, via the Pico

The one item that would fix the overlay showing defaults after a power cycle. The core cannot
tell the overlay what it restored, and only the Pico owning the settings file fixes that.

Needs the FPGA to act as a block device for the Pico's filesystem, arbitrated against Nextor.
Real work, and a mistake corrupts the card rather than a setting. MiSTeryNano's `sd_card.v` is
the reference.

### C2. The SFG-05's FM synth

JT51 behind the OPM registers. An eight-channel four-operator synth does not belong on a device
at 88%.

### C3. `.CAS` cassette support

`MSX1_MiSTer/rtl/tape.sv` is reusable, GPL v2+.

---

## Why the ordering is by cost

Three builds were lost to a timing problem that none of the obvious explanations predicted. One
of them came in **under** the passing build's resource count, touched nothing in the failing
clock domain, and still failed badly.

Timing here is governed by **placement**, not by how much logic you add. So "it is only a small
change" is not a defence, and every RTL item carries a risk that a menu item does not. That is
the entire reason Group A goes first.

The measured history is in [UTILISATION.md](UTILISATION.md).
