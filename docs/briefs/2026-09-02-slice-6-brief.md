# Slice 6 brief — the last cable swap

**Date issued:** 2026-09-02
**Prerequisite reading:** `docs/decisions.md` D15 (this slice exists because of it), the
Slice 5 section of `docs/protocol-findings.md` (especially Task 1 and Task 4), and
`docs/protocol-discovery.md` — **all of it**, including which routes are closed.

---

## What this slice is

One programming session against the head, then **one** cable swap, then a decision.

The owner has agreed to spend one more swap. He has spent nine. Design the batch so that
whatever the disc shows — including nothing — the result is unambiguous, and treat this as
the last observation this project will ever get.

If the disc stays dark, the hardware path closes for good. That is an outcome to record
plainly, not a failure to explain away.

## What is being tested

Slice 5 gave us the sibling's table format from the serializer itself. E2a/E2b already
wrote that table to our head and got nothing — but they wrote it at base 0, in the
community's reconstruction of the format, before we had the real one.

The live question is whether the table is right but **positioned wrong**. Our head's only
distinctive behaviour is that `A0` writes with a second byte in **0x18–0x23** take tens of
milliseconds or stall for five seconds, in four independent runs, regardless of payload.
That is where the firmware does something. A plausible reading is that the message-length
or table-header fields live in that range, and every stream we have written put its length
bytes somewhere else.

## Design rules for the batch

1. **One primary candidate.** Candidates that write overlapping address ranges cannot be
   tested together — the last write wins. Pick the single layout the slice-5 analysis best
   supports, place it where the analysis says the table belongs, and commit to it.
2. **Hedges only at non-overlapping bases.** A second copy at a high base (0x400 and up) is
   free and catches the case where the parser's base is not what we think.
3. **Every candidate gets a distinct visual signature.** This is the point of the design. If
   the disc lights, the shape must tell us *which* candidate produced it without a second
   swap. Use unmistakably different content per candidate — a row of `I`, a row of `8`, a
   solid block. Do not use the same text twice.
4. **Derive the byte layouts from the serializer you mapped**, not from this brief. You have
   the ground truth at file `0x01f7f0` and the upload routine at `0x020290`; I do not.
   Compute where the length fields land and choose the base accordingly.
5. **Write the exact packet stream to `Tools/probe-output/` before sending it**, so the
   experiment is reproducible and the record survives the session.

## Retired — do not test

**The `A0 <length>` + continuation-packets hypothesis (route 1c) is retired.** It was mine,
from the observation that the stall range brackets 26. Slice 5 weakened it: the family's
framing is a 2-byte header plus five stream bytes plus a checksum, with a mandatory 3-byte
acknowledgement, and nothing in the vendor's serializer resembles a length-then-continuation
shape. It also conflicts with the EEPROM-write model at the address level, so testing both
in one batch is impossible. The EEPROM model has four runs of timing evidence behind it; the
length reading has an arithmetic coincidence. Spend the swap on the better-supported one.

Update `protocol-discovery.md` to mark 1c retired, with that reasoning.

## The owner's part — write it out for him

Produce a short, exact checklist before he touches anything: which cable, which order, what
to run, how long to wait, what to look for, and what counts as a result. He is doing the
observing and he only does it once.

Include what a *partial* success looks like. Any light at all — a smear, one lit column, a
flicker as it spins up — is a result and must be recorded exactly as seen, not rounded to
"it didn't work".

## Acceptance

- [x] The batch is designed, justified against the slice-5 layout, and the packet stream is
      written to `Tools/probe-output/` before sending.
- [x] Each candidate has a distinct, documented visual signature.
- [x] The owner's checklist is written and in the report.
- [x] The observation is recorded verbatim in `docs/protocol-findings.md`, including a
      negative.
- [x] If dark: `protocol-discovery.md` and `hardware.md` are updated to state the hardware
      path is closed, with a one-paragraph summary of everything that was eliminated. Write
      it for someone arriving in two years with the same fan.
- [ ] If lit: stop. (Not applicable: the disc stayed dark.) Do not chase it further in this slice. Record exactly what was sent and
      what appeared, and hand it back to the architect — a working write changes every
      remaining decision and deserves a fresh brief.

## Out of scope

- Feature reports (D7 still stands — declined without a specific hypothesis).
- Any change to `LedFan/` source. This slice produces knowledge.
- More than one cable swap. If the batch is not ready, do not spend it.

## Definition of done

1. `protocol-findings.md` records the batch, the layouts, the reasoning and the observation.
2. An acceptance report at `docs/reports/2026-09-02-slice-6-*.md` with the usual "where the
   brief was wrong" section.
3. The closing summary written, in whichever direction the result points.
4. Everything committed.
