# Porting a retro core to a Tang board — the playbook

**`FPGA_WORKFLOW.md` is the reactive half: rules written after a bug, to stop it
recurring. This is the proactive half: the order to do things in, with each
known trap placed at the step where it actually bites.**

Written 2026-08-30 from the real history of MSXHeroTN, PCEHeroTN, NextHeroTN,
CoreSwitch and the X68000 measurement. Every claim here cost something.

**Read this before starting a new core. Read `PARTS_CATALOGUE.md` beside it —
most of what a port needs already exists.**

---

## The shape of the whole thing

```
-1  Does it fit?          measure, never estimate
 0  Pick a base           and settle the licence before writing RTL
 1  Build the channels    UART and simulation, BEFORE you need them
 2  First bitstream       utilisation and timing, nothing else
 3  Visible stages        each build ends in something you can look at
 4  The memory system     the hard part, every time
 5  Input, sound, polish
```

**Steps -1 and 1 are the two everybody skips, and they are the two that decide
how long the project takes.**

---

## Phase -1 — Does it fit? Measure, never estimate

**The estimate has been wrong every single time, in both directions.**

| Estimate | Reality | Factor |
|---|---|---|
| PCEHeroTN block RAM, counting bits | counting *blocks*, then counting them properly | 93% → 111% → **133%** |
| X68000 video chipset | 8,000–12,000 LUT4 estimated | **~1,650 measured — 5× wrong** |
| X68000 DMA controller | assumed small next to the CPU | **7,765 LUT4 — larger than the CPU** |

So: **synthesise each block separately and read the number.** One `TOPMOD` at a
time, synthesis only, no place-and-route. A day of this replaces a month of
argument, and it has reversed the verdict twice.

**Four traps, all of which have cost a run:**

1. **Stub memories must derive their output from the address.** A stub returning
   a constant lets the optimiser prove whole downstream paths are compile-time
   constant and fold them away — the report then shows a fraction of the truth.
   X68000's palette measured **1 LUT** this way.
2. **Name the top module explicitly.** Without it the tool picks one by
   heuristic and can prune the entire netlist, reporting almost nothing —
   which looks like a result rather than a mistake.
3. **Presence in a directory is not evidence of use.** Only the instantiation
   tree counts. X68000's `vidcont` did not cover two files sitting next to it.
4. **Check for "swept in optimizing" in the log.** A module that was fully
   elaborated and then flattened is fine; a module that vanished because a stub
   made it dead is not. Distinguish them before trusting a surprising number.

**Count block RAM in blocks, not bits.** The vendor allocates whole blocks and a
memory's *shape* decides how many it burns. A 32768×16 VRAM needs 28.4 blocks of
bits and consumes **32**.

**And remember the answer may be "a bigger board".** That is a result, not a
failure. Finding it in a day is the win.

---

## Phase 0 — Pick a base, and settle the licence before writing RTL

**Survey more than one implementation.** They differ in size, in accuracy, in
where memory lives, and in what has to be thrown away. PCEHeroTN surveyed five
and the survey changed the plan.

**Prefer a base that already has a small-FPGA mode.** MiSTer's TurboGrafx16 has
a `LITE` generic that drops the cheat engine and the second video chip — exactly
the trim wanted, already written and maintained by someone else.

**Prefer the branch whose ports match what you need**, not the most accurate
one. PCEHeroTN takes its video chip from the MiST branch purely because it kept
a `RAM_RD` output that MiSTer's dropped.

**Settle the licence now.** Not after a week of work.

- Retro FPGA cores are frequently **unlicensed** — no grant at all, which means
  no right to redistribute. FPGAPCE, the ancestor of every PC Engine core, says
  *"All rights reserved"*.
- GPL obligations attach to **distribution, not sale.** Giving away a bitstream
  is distributing. "It's free" is not a defence.
- Private experimentation carries no obligation. The decision only bites at
  publication — so make it **deliberately**, in writing, at the start.

---

## Phase 1 — Build the channels before you need them

**Do this on day one. It is never justified on day two, and it is the single
biggest multiplier available.**

### The text channel

A UART transmitter in the fabric: shift register plus baud divider, well under
100 LUTs, no block RAM. On a Tang Nano 20K the on-board BL616 bridges it to USB
serial with no extra hardware.

**The pins are not in the datasheet. They are in working code.** On the TN20k,
**pin 69 is the FPGA's UART TX and pin 70 the RX**, through the USB-C port —
named in `MiSTle-Dev/bl616debugdisplay`'s `.cst` and in MSXHeroTN's own
`tang9k.cst`. The vendor datasheet documents none of this and a whole debug
channel was abandoned on that basis.

**A transmitter is already written**: `MSXnano-MiSTle/fpga/src/uart_tx.v`.

**Why it matters:** PCEHeroTN spent a week debugging a ~2000-signal design
through six LEDs. Each yes/no question cost a build, a flash, a walk to the
monitor, and several power-cycles. Text would have printed the answer.

### The simulation

GHDL or equivalent, running the real core with a real ROM. Full visibility,
deterministic, seconds per run.

**Write its blind spot into its own README at the time you build it.** Every
harness stubs something, and the stub is invisible to it. PCEHeroTN's testbench
stubs the two Verilog memory files — **precisely where the only confirmed bug
lived** — so a clean simulation says nothing about the thing that is broken.

**They answer different questions and you want both.** Simulation finds logic
bugs; the UART finds the ones that only exist on real silicon with real timing.

---

## Phase 2 — First bitstream: utilisation and timing, nothing else

Featureless on purpose. No video, no sound, no ROM. It answers two questions and
they are the ones that can still say no: **does it fit, and does it close
timing.**

**"It fits" is not "it closes".** MSXHeroTN fits at 87% of its logic and its
timing is placement-dominated. Utilisation and Fmax are different answers.

**Expect an over-utilisation failure here and have the response ready** — a
smaller variant, VRAM moved out — rather than treating it as a surprise.

---

## Phase 3 — Bring up in visible stages

**Order the stages so each one ends in something you can look at.** Phase 0 of
PCEHeroTN spent six builds producing numbers and only the last produced a fact.
Phase 1 was staged instead:

```
1.1  video output, test pattern only    -> colour bars on a TV
1.2  point the core's video at it       -> bars in the pillarbox
1.3  move VRAM to its real home         -> picture unchanged (a refactor)
1.4  the ROM                            -> a title screen
1.5  the pad                            -> playable
```

**1.1 deliberately has nothing to do with the machine being ported.** Going
straight to core-on-HDMI leaves four suspects on a black screen — video chip,
scaler, wiring, clocks — and this removes three of them in one build.

**One variable per build**, and check what the build cost before flashing. A
change that fixes the logic and eats the timing margin is not a fix.

---

## Phase 4 — The memory system. This is the hard part, every time

**Three projects have been blocked here and it is the same problem each time.**

### Take the controller from someone who ships on your board

`MiSTle-Dev/NanoMig`'s `src/misc/sdram.sv` says in its header that it is for
*"the MiSTer SDRAM, the TN20k etc"*. GPLv3, two ports, and it works.

**Do not adapt a controller built for a different machine.** That is not reuse,
it is building new with extra steps and a misleading air of safety. PCEHeroTN
adapted MSXHeroTN's controller — proven on the same board — and paid four bugs
and a week, because it was built for a Z80 and a V9958: a different clock ratio,
a refresh signal the new machine has no equivalent of, and a memory client that
can be stalled when the new one cannot.

### The four choices, on which three independent designers agree

Torlus (FPGAPCE), harbaum (NanoMig) and nand2mario (NESTang) all made these, and
PCEHeroTN made the opposite call on all four:

| Do | Not |
|---|---|
| **A separate port per requester** | one shared port with slot arbitration |
| **One `sync` pulse; the controller derives its own schedule from a clock ratio** | phase corners handed to it |
| **An explicit `refresh` input** | inheriting refresh from a CPU signal |
| **`req`/`ack` per port, and wide reads** | a transient to catch, one word at a time |

**The second is the one that matters most.** Keying anything to a specific phase
corner couples it to a video timing **the software can change at runtime**. A
PC Engine game writes its own dot clock as its sixth instruction; the corner the
controller was waiting for stopped existing and the machine froze solid.

**And the objection you will raise against this is probably wrong.** PCEHeroTN's
notes rejected NanoMig's design for a year's worth of good-sounding reason:
*"our video chip has no ack and cannot wait."* Neither can the Amiga's. That is
**why** the design takes one sync pulse and computes a fixed schedule — so an
unstallable client is served at a guaranteed latency with nothing to wait for.

### Clock the memory chip with a phase-shifted clock

```systemverilog
.clk               ( clk_85m )            // the controller's logic
assign O_sdram_clk = clk_85m_shifted;     // the chip's clock pin
```

On a Gowin rPLL: `CLKOUTP` with `PSDA_SEL = "1100"` — 12/16, **270°**.

Without it the chip samples and drives data on the same edge the FPGA's logic
switches on, with no margin. It works nearly always, and "nearly" presents as
one bad word in millions. **PCEHeroTN clocked it unshifted from day one.**

### Feed a client that cannot wait

Its address is valid for one dot period and there is no way to stall it. Two
things follow:

- **The request is a level, not a pulse to catch.** The controller samples it
  continuously while waiting for its slot. No latching adapter needed.
- **Give the CPU a wide read.** Torlus returns 64 bits per ROM read for exactly
  this reason: a 6502-family CPU fetches sequentially, so one access feeds many
  bytes and the CPU never starves. Discarding three of four bytes from a 32-bit
  read cost PCEHeroTN a day.

### Prove the controller alone, before anything depends on it

Its own build, no core at all: write an **address-derived** pattern across the
whole chip, read it back, compare, report the count as a number.

**Address-derived matters.** A constant passes against a chip returning a stuck
value everywhere and against a decoder aliasing every row onto one.

**Loop it, and read the number twice a minute apart.** One pass cannot tell a
start-up artefact from an ongoing fault. And make later passes **read-only**
against data written once: that separates a bad write from a bad read, and
doubles as a refresh soak.

A ready-made example: `PCEHeroTN/rtl/pcehero_sdtest_top.v`, and an older one in
`MSXZero/fpga/bringup/sdram_test_top.v`.

---

## Phase 5 — Input, sound, polish

Cheap by comparison, and mostly catalogue work. See `PARTS_CATALOGUE.md`.

One note worth keeping: **a real console with no controller still shows its
title screen.** "The pad isn't wired" never explains a black screen.

---

## The two habits that matter more than any of the above

**Measure activity, not values.** Most bring-up bugs are handshakes — two
parties each waiting on the other — and they leave *every value in the system
correct while nothing moves*. A diagnostic that checks a value is blind to them.
Count things. Latch did-this-ever-happen bits.

**Every instrument needs a bit that says when it is lying.** Ask before building
it: *if this reads dark, how many different things could that mean?* If more than
one, add a bit that separates them and read that bit first. **Five instruments
on PCEHeroTN gave confident wrong answers**, and the fifth was written the same
day that rule was.
