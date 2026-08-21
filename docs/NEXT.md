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

### A1. Make the browser behave — **in progress, 1.1**

Four things, all in or near the routine that builds the listing (`scan_current`), so they are
one piece of work rather than four passes through 6,000 lines of someone else's Z80.

**Hide OS housekeeping — done.** The scan tested `ix+11` for volume label and directory but
never for hidden (`0x02`) or system (`0x04`), and the `'.'` test only sees the *short* name, so
`.Trashes` — short name `TRASHE~1` — sailed through. Every card formatted on a Mac or PC
carried `.Trashes`, `.fseventsd`, `._*` and `System Volume Information` into the listing, eating
slots against the 115 limit. Four instructions. Also hides Nextor's own `NEXTOR.EMU`, which is
created hidden+system precisely so it stays out of sight.

**Sort the listing — next.** There is no sort anywhere in the file; entries appear in raw FAT
directory order, which is the order they happened to be written. This is the biggest single
usability win, and it makes the 115-file limit hurt less because you can predict where a name
falls.

Do **not** sort the 80-byte records in place: 115 entries insertion-sorted means roughly 6,600
swaps of 80 bytes each, which is around three seconds on a 3.58 MHz Z80. Sort a 115-byte index
table instead and have the render path read through it — same algorithm, a byte moved per swap
instead of eighty.

**Remember the position.** After a reset you are back at the top of the root. Keeping the last
directory and cursor position matters more once A3 stops resets landing here at all.

**Then the 115-file limit** (was A4), which is the same routine again.

### A2. Tidy the keys

**Three keys are dead.** The browser's dispatch still handles `W` (WiFi config), `U` (UNAPI
test) and `F` (File-Hunter, the online ROM search). All three need the ESP-01S, which this fork
compiles out — at best they do nothing, at worst they hang on a missing UNAPI. Remove them
until WiFi comes back (B2).

**One key is undocumented.** `/` runs a working name search (`.br_search`) and the status bar
never mentions it. Free feature nobody knows exists.

**`S` goes too.** Its only remaining job was saving to flash, which the F12 overlay does as of
1.0. Compatible Mode — the one setting that screen had which the overlay lacks — was deleted
upstream in v1.9, so nothing is lost. Removing the settings screen also frees Z80 space the
115-file fix needs.

Note the status bar is width-padded: `"R/D/A=Filter ESC=Boot S=Save F12=Setup TAB=Part H=Help  "`
must stay its exact width as entries come and go.

### A3. Drive the browser with a joystick — **already implemented, needs testing**

**Do not build this.** It exists. Found while starting work on it:

`browse_getkey` polls the joystick alongside the keyboard, via `poll_joy` and `read_joy_code`
(around line 2810). It uses the BIOS `GTSTCK`/`GTTRIG` on **port 1**, edge-detected against
`JOY_PREV` so holding the stick gives one event per push, with auto-repeat after
`JOY_RPT_DELAY` = 14 frames at `JOY_RPT_RATE` = one step per 2 frames.

| Input | Does |
|---|---|
| up / down / left / right | the cursor keys — left and right page |
| trigger A | RETURN — launch |
| trigger B | BACKSPACE — parent folder |

It should already work with the shield's DB9 stick, which defaults to MSX port 1, and with a
USB pad, since both feed the same PSG lines.

**So the task is to test it, not to write it.** If it works, this item closes for free. If it
does not, how it fails narrows the cause immediately: nothing at all points at the port or the
PSG mixing, wrong directions at the `GTSTCK` decode, constant firing at the edge detection.

Worth remembering as a general lesson — this menu is 6,000 lines of someone else's Z80 and it
does more than the status bar advertises. Read before building.

### A4. (folded into A2)

`S` opens a reduced on-MSX settings screen. Its only remaining job was saving to flash, and the
F12 overlay does that now — so it is redundant as of 1.0.

Two `cp #53` handlers at lines 451 and 2054, plus the settings screen itself. Note the status
bar is width-constrained: `"R/D/A=Filter ESC=Boot S=Save F12=Setup TAB=Part H=Help  "` is padded
to a fixed width and must stay that width when `S=Save` comes out.

Worth doing before A4, because deleting the settings screen frees Z80 space that A4 needs.

### A5. Reset should relaunch the game, not the browser

On a real MSX with a cartridge inserted, the reset button restarts the game. Here it lands in
the browser, because the browser *is* the boot ROM and runs before the OS on every reset.

That makes Reset do Cold Boot's job while Cold Boot does nothing distinct. The pair should be:

| | Behaviour |
|---|---|
| **Reset** | restart what is running — straight back into the game |
| **Cold Boot** | drop the cartridge, land in the browser to pick something else |

**This half needs no FPGA build.** The menu can do what the MSX's own slot scan does: look in
the megaram for a valid cartridge header, and if one is there, boot it immediately rather than
drawing the browser. Pure Z80.

It interlocks with B3 — once Cold Boot invalidates that header, it lands in the browser
naturally, because the menu looks and finds nothing.

**Test rather than assume:** SDRAM contents are not guaranteed zero at power-on, so garbage
could in principle look like a header. The MSX's own slot scan already takes that risk, so it
is not new, but a magic signature written by the loader would be sturdier than trusting two
bytes. Worth deciding before writing the check.

### A6. Remove the 115-file limit

The browser silently lists only the first 115 entries of any directory — no warning, they simply
are not there. The listing lives in a fixed array in MSX RAM, 80 bytes per record:

```asm
MAX_ENT  equ  115    ; 115*80 = 9200 bytes -> C300..E6F0
```

Fixing it means paging the listing rather than holding all of it, which is more involved than
the items above but still Z80-only. The space freed by A2 helps.

---

## Group B — small RTL. Needs a PC build, so timing is a real risk.

Each of these adds a leg to the `cpu_din` read mux, which is the structure that governs timing
here. Do them **one at a time**, so a timing regression has one suspect.

### B1. MIDI ports

Two registers and a 31250-baud UART on pins 71 and 72, which are free. The FM chip is *not* part
of this — see C2 for why the synth is a separate question.

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

### B3. Make Cold Boot mean something

**Reset and Cold Boot are currently identical.** The core asserts reset on `~(|system_reset)` —
non-zero — and the overlay sends 1 for Reset and 3 for Cold Boot. Both are non-zero, so both
pull the same line for the same 10 ms. The distinction the protocol offers is thrown away.

Two things should distinguish them, and neither does.

**The cartridge stays plugged in.** Found on hardware: load a game, choose Reset, land back in
the browser, press ESC to boot the MSX — and the game runs again. That is not a fault. A ROM is
copied into the megaram, which is SDRAM and survives a warm reset, so the MSX's slot scan finds
a valid cartridge header in slot 3-3 and boots it, exactly as a real MSX boots a cartridge left
in the slot. At power-on the megaram holds garbage, no `AB` header is found, and the machine
goes to Nextor instead — which is why a power cycle behaves differently.

**Boot-turbo never applies.** `boot_done` is set the first time the CPU leaves reset and never
cleared, deliberately surviving warm resets, and boot-turbo is applied only when it is 0. So
choosing Cold Boot does not start the machine in turbo; only cutting the power does. The XML's
own comment on `cold_reset` claims otherwise.

So the two should be:

| | Behaviour |
|---|---|
| **Reset** | reboot with the cartridge still inserted — what happens today |
| **Cold Boot** | reboot as if nothing were plugged in, and re-apply boot-turbo |

This is the other half of A3, and the two should be designed together.

For the cartridge half, the machine only needs to stop finding a header where one used to be:
either clear `config1_ff[1]` so the megaram is not mapped for that boot, or invalidate the
header bytes. Note the ordering — `config_init` reloads `config1_ff` from flash *during* the
reset, so a cold-boot flag has to be applied after that, not before.

For the turbo half, have `system_reset[1]` clear `boot_done`.

Small, but it is RTL, so it belongs in this group rather than in A.

### B4. USB mouse

The roadmap calls this small because the Pico already decodes mice and the line in
`fpga_companion.v` is only commented out. **Verify that before believing it** — the missing
piece is likely the MSX-side mouse protocol on the joystick port, which is more than
uncommenting a line.

---

## Group C — big, and each needs a decision before it needs a developer

Not "later" as a polite no. These are all worth having; they are just large enough that
starting one without deciding it is worth the risk would be a mistake. This core is at 88% CLS
with `clock_54m` closing by 0.3 MHz, and every one of these adds significantly more than the
Group B items.

### C1. Settings on the SD card, via the Pico

The one item that would fix the overlay showing defaults after a power cycle. The core cannot
tell the overlay what it restored, and only the Pico owning the settings file fixes that.

Needs the FPGA to act as a block device for the Pico's filesystem, arbitrated against Nextor.
Real work, and a mistake corrupts the card rather than a setting. MiSTeryNano's `sd_card.v` is
the reference.

### C2. The SFG-05's FM synth

JT51 behind the OPM registers. Bigger than the OPLL already in the design, and this chip is at
88% CLS with 0.3 MHz of timing margin — so the honest position is that it probably does not
fit, and finding out costs a synthesis run rather than an argument.

Worth doing that run before assuming either way. If it does not fit, B1 still gives you working
MIDI ports for driving external gear, which is what most MSX MIDI software wants anyway.

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
