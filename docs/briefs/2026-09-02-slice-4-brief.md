# Slice 4 brief — make the preview real, make the refusal honest

**Date issued:** 2026-09-02
**Prerequisite reading:** `docs/decisions.md` D6–D9 (new, and they answer slice 3's open
questions), then D1 and D5. `docs/protocol-findings.md` end-of-day summary for context.

---

## Where we are

Slice 3 closed the probing session. Every published lead is exhausted, the head is
write-only, there is no live oracle — the data port is on the rotating head, so each
observation costs a cable swap — and a blanket header sweep erased the factory demo.

**Milestone 2 is paused (D6).** Not abandoned: paused until the message table format
arrives from outside, most likely from an EEPROM dump of an unmodified sibling fan
(`protocol-discovery.md` route 1b, new).

That makes the on-screen preview the entire visible product. It currently draws "HELLO" as
unreadable spokes. **Fixing that is the most valuable work available**, which reverses slice
3's suggestion that angular resolution now matters less. It matters more.

This slice ships no new probing. Do not send bytes to the fan.

---

## Task 1 — Commit everything, first, before any code

**30 uncommitted paths across two slices**, including `docs/protocol-findings.md` — a day of
irreplaceable findings and nine of Willie's cable swaps, living only in a working tree.

Commit slice 2 and slice 3 as two separate commits, in that order, with messages describing
what each established. Do this before touching anything else.

**Acceptance**
- [x] `git status --porcelain` is empty.
- [ ] Slice 2 and slice 3 are distinguishable in `git log`. (Not done: they were already committed together as `7be831d` before the slice; see the report.)
- [x] Nothing in `Tools/probe-output/` was dropped — those are primary evidence.

---

## Task 2 — Implement D1: the preview becomes legible

The rasterizer keeps producing a strip; a new composer maps that strip into one revolution
at fixed angular resolution.

**Contracts (from D1, unchanged):** `FanGeometry`, `ColumnStrip`, `POVFrame` with
`columns.count == geometry.columnsPerRevolution`, `MessageRasterizing.strip(for:ledsPerArm:)`,
`FrameComposing.frame(from:geometry:columnOffset:)`.

Per D5, these are **preview-only** concerns now. `columnsPerRevolution` is whatever makes
the preview legible; it makes no claim about hardware. Start at 180 and tune by eye.

**Acceptance**
- [x] A 26-character message renders as recognisable text in the preview.
- [x] A short message does not spread across the whole circle — it occupies a proportional
      arc, with the remainder dark.
- [x] `columnOffset` shifts the message around the disc. Prove it in a test; do not wire a
      scroll animation yet.
- [x] Rasterizer stays pure and free of geometry.
- [x] Screenshot evidence, both appearances, in `docs/reports/images/`.

The last box is the real one. Ticking the others without a legible screenshot is not done.

---

## Task 3 — Implement D5: messages live in slots

`FanMessage { slot: Int, text: String }` with `maximumCharacters = 26`, `slotCount = 8`.
`FanDisplayTransport.store(_:)` replaces `display(_:)`. `geometry` replaces `ledsPerArm`.

**Acceptance**
- [x] Slot picker, 1–8, in the controls card.
- [x] Live character counter against the 26-character limit.
- [x] Over-length input is visibly truncated or refused — never silently cut.
- [x] Validation lives in the domain type, not the view.
- [x] Editing per-slot text is retained in memory while the app runs; persistence is not in
      scope.

---

## Task 4 — Implement D8: split the encoder

`EEPROMWriting` is **known** and fully testable: `A0`, address, up to six data bytes per
8-byte report. `MessageTableSerializing` is the **unknown** and throws
`.protocolNotYetKnown`.

**Acceptance**
- [x] `EEPROMWriting` unit tested: packet size always 8, address increments by the payload
      length, final chunk padded, a 26-character payload produces the expected packet count.
- [x] The 0x18–0x23 address range is annotated in code as where the firmware stalls — two or
      three lines, per the comment budget.
- [x] `MessageTableSerializing` has exactly one conformance, which throws, and it is the only
      place in the app that admits the protocol is unknown.

---

## Task 5 — Implement D9: refuse honestly

The app must never write to the head. `HIDFanTransport.store(_:)` throws
`.protocolNotYetKnown`.

**Acceptance**
- [x] Selecting the hardware transport connects and reports the device, and the UI states
      plainly that the fan's message format is not yet known, so messages cannot be sent to
      it yet.
- [x] Send is disabled — not enabled-then-failing — when the hardware transport is selected.
- [x] The copy does not imply a fault in the user's setup. This is our gap, not their cable.
- [x] No code path in the app target can emit a packet to the device.

---

## Task 6 — Correct the specification

Slice 3 found three places where the docs were wrong. Fix them at the source, not only in
the report.

- [x] `protocol-discovery.md` describes the interrupt-IN endpoint and feature report as
      feedback channels. On this head neither carries anything. Say so.
- [x] The docs assume live observation. There is none; the oracle is a cable swap. Say so
      wherever a method implies watching while sending.
- [x] `hardware.md`'s bricking guardrail warned about the wrong failure. The risk that
      materialised was an erased EEPROM, not a dead MCU. Rewrite it.
- [x] `testing.md`: add that no automated test may write to the head.

---

## Out of scope — explicitly

- **No probing.** No sweeps, no structured guesses, no feature reports (D7).
- **No writes to the fan from anywhere**, tools included, without Willie present and asking
  for it.
- No scroll animation. `columnOffset` is proven by test this slice; animating it is
  Milestone 3.
- No persistence, no image support, no additional third-party dependencies in the app
  target. `Tools/` may keep hidapi.

---

## Definition of done

1. Builds with no warnings; all tests pass.
2. Every box above is ticked only where demonstrable, and `features.md` is updated to match.
3. Screenshots of the legible preview in both appearances.
4. An acceptance report at `docs/reports/2026-09-02-slice-4-*.md`, including — as slices 1
   and 3 both did well — a section on where this brief was wrong.
5. Everything committed.

## Note

Slice 3's write-up is the best artefact this project has produced. The decision to stop
rather than spend more of the owner's swaps was the right call and was made at the right
time. Keep that instinct: this slice has a clear end, and reaching for the fan is not part
of it.
