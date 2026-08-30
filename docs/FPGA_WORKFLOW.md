# FPGA bring-up workflow

Portable across MSXHeroTN, PCEHeroTN, CoreSwitch, NextHeroTN, MiniST and anything after them.

Written after 2026-08-25 on PCEHeroTN: eleven real bugs in one day, and most of the lost time went
not to hard problems but to **measuring the wrong thing, or not measuring at all.**

---

## Before you start: read the project's own docs

**Every project here carries hard-won knowledge in `docs/`. Read it before touching anything.**

| File | Why |
|---|---|
| `BUILD_NOTES.md` | what was tried, what failed, and why. Usually answers the question you are about to ask. |
| `DIAGNOSTICS.md` | the LED map, and **the verified / not-verified table** — the single most valuable page |
| `PLAN.md` | which phase this is and what "done" means |
| `INTEGRATION.md`, `PORTING.md` | budgets and decisions made when porting |

**The verified table is the one that matters.** It tells you what has already been proven, so you do
not debug it twice, and — more usefully — what has *never been executed*, which is where the next bug
is.

**Two cautions, both learned the hard way:**

**Your own past comments can be wrong.** A comment in PCEHeroTN confidently explained why ROM
mirroring made the reset vector reachable. The datasheet said otherwise, and an outside analysis
repeated the same error because the comment sounded authoritative. **Comments record what someone
believed at the time, not what is true.** Check load-bearing ones against the datasheet.

**Warnings written earlier are worth heeding.** `pce_slots.v` carried a note saying its alignment was
"the assumption to check first if graphics come out nearly right." The alignment was indeed the
problem — it just failed harder than predicted, starving the CPU entirely. The warning was right and
went unread for a day.

## Rule minus-three: look for it before you write it — and look wider than your own shelf

**Somebody has almost certainly already solved this on this board. Go and find them first.**

Every hour this workshop has lost to a hard problem, the answer already existed somewhere
readable. Not in theory — in a file, on disk or one `gh` command away.

| We were about to write | It already existed |
|---|---|
| an SDRAM controller for a video chip that cannot wait | `NanoMig/src/misc/sdram.sv`, header says *"for the MiSTer SDRAM, **the TN20k** etc"* |
| a UART to get text out of the fabric | `MSXnano-MiSTle/fpga/src/uart_tx.v`, **already wired to pin 69 and switched off** |
| a wide ROM read to stop the CPU starving | Torlus returns 64 bits per read and says why |

**But the rule is not "reuse", it is "search".** Those are different, and confusing them is what
actually cost this project its worst week.

`memory_ctrl.v` **was** reuse. It came from MSXHeroTN, it was proven on this exact board, and
reaching for it felt like exactly this rule being followed. It produced four bugs and a week of
debugging, because it was built for a **Z80 and a V9958** — a different clock ratio, a refresh
signal that this machine has no equivalent of, and a memory client that can be stalled. Every one
of those four bugs was that mismatch surfacing.

**Reusing something built for a different machine is building new, with extra steps and a
misleading air of safety.** The familiar part on your own shelf is the one you will reach for
without searching, and it is the one whose assumptions you will not notice, because you never had
to read it to understand it.

So:

* **Search before you write.** `gh search repos`, the author's other cores, the boards repo, and
  your own other projects — in that order, not the reverse. Your own shelf is the *last* place to
  look, not the first, because it is the one you will find by accident anyway.
* **Prefer what was written for THIS board and THIS problem** over what is merely available and
  familiar. "Proven on this chip" is worth less than it sounds if it was proven doing something
  else.
* **When you find a candidate, read its header and its port list before its code.** Both of the
  finds above announce their intent in the first ten lines.
* **Three independent implementations agreeing is a design decision, not a coincidence.** When
  Torlus, NanoMig and nand2mario all made the same four choices and we had made the opposite call
  on all four, that was the answer arriving unasked — and it sat in the notes for five days before
  anyone acted on it.
* **Write down why you did NOT reuse something**, in the commit. "Ours differs because X" is a
  claim that can be checked later; silence cannot.

**And check the documentation you are trusting is the documentation that is true.** The Tang
datasheet documents no BL616 UART pins, and a whole debug channel was abandoned on that basis. Two
working projects' `.cst` files name the pins plainly — including one of ours. **A vendor datasheet
is one source, not the source.** Working code that ships on the board outranks it.

## Day one: build the text channel before you need it

**Do this at the start of a project, not after a week of LED debugging.**

Six LEDs is a handful of bits per build-flash-carry-to-monitor cycle. Every
question costs twenty minutes and has to be guessed in advance. Two channels
remove that, and both are cheap:

- **A UART out of the fabric.** Shift register plus baud divider, under ~100
  LUTs, no block RAM. On boards with a USB-serial bridge (the Tang Nano 20K's
  BL616, for one) the text lands on the host with no extra hardware. It prints
  values, in order, with no decoding by eye — and it works on **real silicon
  with real timing**, which simulation cannot reproduce.
- **A simulation testbench.** Full visibility, deterministic, seconds per run,
  and observation costs nothing.

They answer different questions and you want both. Simulation finds logic bugs;
UART finds the ones that only appear on hardware.

**The trap that stops you building them:** every next question looks like one
build away, so a day of tooling never justifies itself. It is justified on day
one and almost never after. PCEHeroTN spent a week debugging a ~2000-signal
design through six LEDs because of exactly that reasoning.

## Rule minus-two: measure the signal, not its consequences

**Three times in one day an instrument nearly sold a wrong conclusion, and every time the cause was
the same: measuring something downstream of the question.**

| Wanted to know | Measured instead | Why it lied |
|---|---|---|
| Is the ROM corrupt? | `rom_do` gated on `rom_rdy` | `rom_rdy` is high while the cache holds a *different* line, so it compared another address's byte |
| Does the CPU write work RAM? | a port declared but never assigned | synthesis optimises an undriven output away and reports clean |
| Does the forced interrupt fire? | `IRQ_VBL`, a flag **software can clear** | reading the VDC status register wipes it, so "not seen" and "seen and handled" look identical |

**Before adding a diagnostic, ask what else could produce the reading you expect.** If a passing
result and a failing result can both come out the same way, the instrument is not measuring the
question.

**Prefer signals that:**

* nothing downstream can clear — a **sticky bit on the source**, not on a flag someone else owns
* software cannot influence — counters and strobes over status registers and interrupt flags
* are **as close to the question as the design allows** — if you want to know whether a pulse
  happened, latch the pulse, not its effect three modules later

**And when a reading is surprising, suspect the instrument before the machine.** On this project the
instrument was wrong roughly as often as the design was.

## Rule minus-one: three questions before touching functional RTL

**Do not modify functional RTL unless you can answer all three:**

1. **What does the original hardware say?** The manual, not a comment, not a forum post, not
   inference from ported code. `docs/datasheets/` has HuC6280, HuC6270, the Tang board and the PC
   Engine schematics.
2. **What does the known-good implementation do?** MiSTer and Torlus both work. If our code differs
   from theirs, that difference is the candidate. **If it is identical, the bug is in what feeds it**
   — and changing it would break a working thing.
3. **Can I put a diagnostic directly on the signal** that distinguishes the two possibilities? If
   not, any change is a guess dressed as a fix.
4. **What would prove me wrong?** If nothing would, it is not a hypothesis. Every theory that cost a
   build cycle here was one that could not have failed a test — because no test had been designed for
   it.

**A safety condition on a test can make it unable to succeed.** The forced-interrupt test was gated
on the game's own enable bit — careful-sounding, and it meant the force never fired on the boots
where the game had not set it. The experiment could neither pass nor fail. **Guard a change; never
guard the measurement.**

**Every wasted cycle in this project failed one of these.** The reset synchroniser fixed a real
violation that could never have caused the symptom — question 3 unanswered. The free-running phase
counter was a net regression — question 2 unasked. The `rom_rdy` rework created a deadlock — question
1 unasked. And the VDC edge-detect looked wrong until it turned out to be character-for-character
identical to MiSTer's, which took thirty seconds to check and would have cost a build cycle plus a
wrong "fix".

**Diagnostics are exempt** — adding a debug port or an LED changes no behaviour. This rule is about
changing what the machine *does*.

## 0. Verify what you just enabled, before building on it

**Every time something was switched on and assumed to work, it did not.**

| Assumed working | Reality |
|---|---|
| A ROM path from flash to CPU | broken in four separate ways |
| A memory controller reused from a working project | built for a clock ratio the new core cannot provide |
| Work RAM, after flipping one generic | enabled and never tested |
| A path assumed **broken** | never once exercised — the assumption ran the other way, equally unfounded |

**When you enable, port or rewire a subsystem, the very next build measures it.** Not the build after
the feature that depends on it — the next one.

The check is nearly always the same shape: **write a known value, read it back, latch the
comparison.**

**Before every build, ask: what in this design has never been executed?** That list is where the next
bug is.

## 1. Measure activity, not values

Handshake bugs — two parties each waiting on the other — leave **every value in the system correct
while nothing moves.** Diagnostics that check values are blind to them.

Count things. Latch did-this-ever-happen bits. A fetch counter says more than a correct byte.

## 2. Prefer signals that move because the hardware moves

Interrupts and status bits are usually **gated on something software enabled**. A dark interrupt
proves nothing if the program never turned it on.

Pick counters, display flags, slot states — things that move because the chip is running.

## 3. Display a value before testing predicates about it

Three builds asking "is this register 2?", "is it 5?" — when five LEDs could show which bits it has
ever held and answer all of them at once.

A **sticky bitwise OR** (`seen <= seen | value`) is usually right: it survives single-cycle values and
needs no trigger.

**But know its limit:** a sticky OR of random data looks identical to a full sweep. If every bit is
set, ask whether garbage would produce the same picture.

## 4. Levels or slow blinks, never fast toggles

Nobody can distinguish "lit" from "blinking at 20 Hz" by eye. A bit that toggles per event reads as
lit whether it fired once or a thousand times.

* **Level** — `led = ~(count > 1)` — unambiguous
* **Sticky** — `if (event) seen <= 1'b1` — catches a one-cycle event
* **Slow blink** — divide to ~1 Hz if you must show a rate

A free-running heartbeat on one LED is worth its cost: it proves the design is alive and the
bitstream is the one you think it is.

## 5. Non-determinism is information

**A deterministic digital system does not behave differently between boots.** If it does, something
uninitialised or marginal is feeding it — and that is usually a bigger clue than whatever you were
measuring.

Always ask for a second boot when a reading is surprising.

## 6. Confirm the build actually contains your change

A build commit landing *on top of* your fix does not mean the bitstream contains it.

**Name the number you expect to move before you flash** — block RAM count, LUT count, a port name in
the built tree — and check the build report for it. And check the build's commit message describes
*your* change, not the previous one.

This matters more the more you reuse LED meanings: a stale bitstream does not fail visibly, it
answers a different question in the same lights.

## 7. Ask for the datasheet

The chip's manual states in a table what takes hours to infer from ported RTL — and RTL tells you
what a *port* does, not what the *chip* is supposed to do.

Keep supplied datasheets in `docs/datasheets/` so they are not lost.

## 8. Bisect: prove the next link, do not guess past it

Keep a **verified / not-verified table** in the repo and update it every session. It is what stops a
thing being debugged twice, and what makes "where has this never run?" answerable.

Each diagnostic should retire one link. The fault then moves one step and the search space shrinks
monotonically.

## 9. Step back when fixes stop revealing progress

If several consecutive fixes are all real and none moves the outcome, look for a **shared root
cause** rather than continuing. On PCEHeroTN four separate bugs turned out to be one structural
mismatch — a controller assuming clock ratios the core could not provide.

And when three independent projects have solved the same problem differently from you, that is
evidence about your design, not about theirs.

---

## 10. When you revert a fix, record which constraint it violated

A revert throws away two things: the broken behaviour, and whatever the fix got
right. Only the first is intended.

**Write down, in the revert commit, the specific requirement the fix broke.**
Not "caused a regression" -- the actual constraint, in one line: *"went low at
reset, and the CPU needs it high there or CE never pulses."* That sentence is
what stops the next attempt from oscillating between two half-right versions.

Without it a signal flip-flops: version A satisfies constraint 1 and breaks 2,
version B satisfies 2 and breaks 1, and each revert looks locally correct while
nobody ever holds both requirements at once. The fix that satisfies both is
usually available and often trivial -- but only visible to someone looking at
both constraints on the same day.

**This cost PCEHeroTN a full day.** `rom_rdy` was written wrong, fixed correctly
(`a39cd2f`), the resulting deadlock also fixed (`a51974d`), then reverted whole
(`1156a74`) because the fix violated "must be high at reset". Both constraints
were real:

- high at reset, or `CPU_CE` never pulses and the loader deadlocks
- low on a cache miss, or the CPU latches a stale byte

The version satisfying both is one line -- `~loading & ~fetching & (~rom_rd |
line_hit)` -- and it was reachable the moment anyone wrote the two requirements
next to each other. Instead the broken form came back and the fault was
rediscovered from the outside, through fifteen builds and a hardware bisect,
the following day.

**Corollary: a reverted fix is evidence, not a dead end.** When a bug resurfaces
later, check whether it was already fixed once. `git log -S` on the signal name
takes seconds and would have saved that day.

## 11. Every instrument needs a bit that says when it is lying

**An instrument whose silence has two causes is worthless**, and you will not
notice which cause you are looking at.

Ask, before building it: *if this reads dark, how many different things could
that mean?* If the answer is more than one, add a bit that separates them, and
**read that bit first**.

Worked examples, all real:

| Instrument | Silence meant | Self-check added |
|---|---|---|
| `GUARD_HIT` / `VDISP_FELL` | guard unreachable, OR the dot clock is dead | `DCK_SEEN` |
| `CR_WRITTEN` | game never wrote it, OR the VDC sees no writes at all | `ANY_REG_WR` |
| `vec_lo_bad` | byte was correct, OR never checked | `vec_lo_seen & vec_hi_seen` |
| VRAM clear | clear ran, OR never completed | counter-done bit |

The last of these caught a real lie: the corruption bits later read dark while
the self-check said the instrument had gone blind. Without it the report would
have been "corruption eliminated", confidently and wrongly.

**Five instruments on PCEHeroTN gave confident wrong answers.** The fifth was
written the same day this rule was, by the person who wrote it.

## 12. Know which signals depend on the thing you are testing

A signal that would read the same whether the test passes or fails proves
nothing, however many times you sample it.

PCEHeroTN read `GUARD_HIT`, `VDISP_FELL` and `DCK_SEEN` identically on **ten
consecutive boots** and concluded the failure was deterministic. It was not:
those are VDC-internal timing signals that do not depend on the game's boot
path at all, so they read identically whether the boot succeeded or failed.
The first instrument that actually looked found the boot varying enormously.

**Before claiming a result from repetition, ask what the signal is a function
of.** Ten samples of the wrong signal is not evidence.

## 13. Correlate the diagnosis and the outcome on the same power-up

Comparing "the LEDs on this boot" against "whether there was a picture on some
earlier boot" is not evidence when behaviour varies between boots — and on a
marginal design it always varies.

Spend one LED on the outcome. PCEHeroTN's reset-vector build carried
`full_init` alongside the vector-corruption bits specifically so a single
reading said *both* what went wrong and whether this boot worked. That is what
made the readings interpretable at all.

## 14. When bits are scarce, report a number, not a boolean

Five LEDs holding a 5-bit value carry far more than five yes/no answers.

`MAX_AR` — the highest VDC register ever written — characterised an entire boot
in one reading and immediately split "no configuration at all" from "reached
the DMA registers". Five separate flags would have needed several builds to say
the same thing.

**Caveat that bit us:** a maximum is not a checklist. `MAX_AR = $13` was
labelled `full_init`, but it only means the highest register written was `$13`
— it says nothing about whether `$05` was among them. **Name the signal for
what it measures, not for what you hope it implies.**

## 15. Know what your test harness cannot see

Every harness stubs something out, and the stub is invisible to it.

PCEHeroTN's GHDL testbench replaces `rom_loader.v` and `memory_ctrl.v` — the
Verilog memory path, and **precisely where the one confirmed bug lived.** So a
clean per-fetch ROM check in simulation means the VHDL side does not corrupt
fetches. It says nothing whatever about hardware.

**Write the blind spot down in the harness's own README**, at the time you
build it. Otherwise a clean run gets reported unqualified, and the search moves
away from the one place that was never tested.

## 16. One variable per build, and check what the build actually cost

Two changes at once means one can undo the other and you learn nothing.
PCEHeroTN doubled the refresh rate and changed something else in the same
build, lost 8% of Fmax, and had to unpick both.

**And check the timing report before flashing.** A change that fixes the logic
and costs the margin is not a fix. `VRAM_BRAM = 1` was meant to remove the last
random variable and instead added eleven setup violations **on the exact path
under investigation** — making a hardware reading off it worthless. That build
was correctly never flashed.

## 16b. Count the errors with a pattern that cannot miss them

**`grep -c 'class="error"'` on a Gowin report returned 0 on a build carrying 31
errors**, because that tool writes `class = "error"` with spaces around the
equals sign. The build was very nearly logged as clean.

```sh
grep -cE 'class *= *"error"' report.html     # tolerant of spacing
```

**This is the same trap one layer down from the one already recorded.**
`pcehero.sdc`'s header warns that the Total Negative Slack summary hides
cross-domain paths, so you must read the detail tables. Here the detail tables
were read — and the pattern used to count them silently matched nothing.

**A grep that returns 0 has two causes: nothing is wrong, or the pattern is
wrong.** That is rule 11 applied to your own tooling. When a check reports
clean on something you expected to be dirty, verify the pattern matches
*something* before believing the zero.

And when you find a counting bug, **re-run the corrected check over the builds
you already signed off**. Those verdicts rest on the broken pattern too.

## 17. Tier your confidence, and say which tier you are on

Not all "ruled out" is equal:

- **Durable** — read from source, re-verifiable any time. *"MiSTer's `huc6260`
  resets these counters; MiST's does not."* This does not decay.
- **Soft** — rests on an instrument. Every LED reading, every probe. If that
  instrument is later found faulty, **everything it ruled out becomes unproven
  again — not disproven.**

Keep the two apart in your notes. When a bug resurfaces, the soft tier goes
back on the table and the durable tier does not. PCEHeroTN ruled out ROM
corruption with a detector that was later found to be lying, never re-verified
it, and lost a day rediscovering it.

## LED conventions (any board, any core)

- **Keep exactly one blinking LED, always, in every build.** It self-identifies
  which end the numbering starts from, for one flop. LED position confusion has
  cost this project time twice, and the person who mislabelled it was the one
  who wrote the map.
- **Sticky bits for "did this ever happen"; counters for "is this really
  happening".** A sticky bit lights on one stray event and reads identically to
  a real one — that is how a single accidental VRAM write looked like a fill.
- **Levels or slow blinks, never fast toggles.** A bit toggling at tens of MHz
  looks dim, not blinking, and "I think it might be blinking too fast to see"
  is not data.
- **Write the LED map into the repo, in the same commit as the build**, with
  what each reading would and would not prove. Not into chat.

## Flashing and hardware (Tang / openFPGALoader specifics)

**Always `-f`.** An SRAM load dies the moment the board is unplugged, and the FPGA then reloads the
*old* bitstream from flash — so every later observation describes a core you did not build.

| Command | Survives a power cycle |
|---|---|
| `openFPGALoader -b <board> x.fs` | **no** — configuration SRAM only |
| `openFPGALoader -b <board> -f x.fs` | **yes** |

**Say explicitly, every time, whether the board can be disconnected.**

**Check the write, not the erase.** `grep "100.00%"` matches the *Erasing* line. A run that erased and
then failed at 0.2% once reported success and left a board unbootable:

```sh
grep -q "Writing:.*100\.00%" log && ! grep -q "fail to write" log
```

Capture output to a **file**, not a shell variable — a progress stream can blow up the shell.

**Always loop the flash attempt.** USB failures are common and clear on retry.

**Finding the board on macOS.** `openFPGALoader --scan-usb` lies, and prints `empty` before listing a
device that is present.

**The vendor-ID check this file used to recommend also lies.** `ioreg -w0 -l | grep -c '"idVendor"
= 1027'` returned **0 six times in a row on 2026-08-30 while the board was plugged in and working** —
it sits on a secondary USB controller there and the property is not reliably readable. Two checks
that did work, and the device name is the reliable one:

```sh
ioreg -p IOUSB -w0 | grep -i "FRIEND"   # the Tang enumerates as "20K's FRIEND"
ls /dev/cu.usbserial-*                  # normal mode presents TWO of these
```

**Two ports means normal mode** — one JTAG, one a plain UART. **One
`/dev/cu.usbmodem*` instead** means the BL616 is sitting in its ROM bootloader (ISP mode), which is
what a held button gives you; it will not flash in that state.

Retry several times before concluding anything, and **never blame the cable.** This is a worked
example of rule 11 inside the rulebook itself: a check whose failure and whose absence look
identical had been the documented method for a week.

## Editing RTL safely

**Replace specific blocks, never text ranges.** A range replacement once deleted a signal that an
earlier edit had inserted inside it; the reference survived and synthesis failed.

**A declared output is not a driven output.** Synthesis does not error on an undriven port — it
optimises it away, the build reports clean, and the LED reports a confident falsehood. A whole build
was lost to exactly this. Check *driven*, not just *declared*, and note that a port connected through
an instantiation's port map is driven while a top-level signal needs its own assignment:

```python
decl = set(re.findall(r"(DBG_[A-Z_0-9]+)\s*:\s*out", t))
drv  = set(re.findall(r"(DBG_[A-Z_0-9]+)\s*<=", t)) | \
       set(re.findall(r"(DBG_[A-Z_0-9]+)\s*=>\s*DBG_", t))
assert not (decl - drv)
```

Before pushing, check every diagnostic signal is **declared exactly once and used**, and that any new
debug port is wired end to end through every level. Instances inside `generate` blocks that are never
built still need legal port maps — give new ports `=> open`.

A failed synthesis costs a whole build cycle. These checks take seconds.
