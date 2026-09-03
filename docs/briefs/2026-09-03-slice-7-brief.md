# Slice 7 brief — Milestone 3: scrolling, persistence, and finishing

**Date issued:** 2026-09-03
**Prerequisite reading:** `docs/decisions.md` D12, D14, D3, D4 and D9; `docs/brief.md`
Milestone 3. You do not need the protocol findings for this slice.

---

## Where we are

The hardware chapter is **stalled, not closed**. Every reachable lead has been tried; what
remains needs either a German web server to come back or a piece of software (the "USB Fan
Version 3.0" editor) that may not exist in public. Nothing a build session can do.

So the app is the deliverable, and it is one slice from finished. **No hardware work in
this slice. Do not touch the fan.**

Treat this as the slice that leaves the project in a state someone could return to in a
year — or hand to someone else — without needing this conversation.

---

## Task 1 — Start from a clean tree

Check `git status --porcelain` first. If anything is outstanding, commit it before writing
code; if it is already clean, this task is done and needs no action.

*(Written this way deliberately. The slice 4 brief asserted "30 uncommitted paths" from a
status the owner had already acted on, and the developer correctly refused to rewrite
history to satisfy it. A brief should state the check, not its stale result.)*

**Acceptance**
- [x] `git status --porcelain` is empty before any code is written.

---

## Task 2 — Scrolling

`FrameComposing.frame(from:geometry:columnOffset:)` already takes the offset and it is
already unit tested. Scrolling is a timer advancing that integer, not new geometry.

**Acceptance**
- [x] A message longer than one revolution scrolls smoothly and wraps without a visible seam.
- [x] A message shorter than one revolution does not scroll by default — there is nothing to
      scroll. Decide and document what a short message does; standing still is a legitimate
      answer.
- [x] Speed is a named constant in the design system, not a literal in a view.
- [x] **Respect Reduce Motion.** `accessibilityReduceMotion` must stop the animation and
      show a static frame. A spinning ring of text is exactly the kind of motion that
      setting exists for.
- [x] The timer stops when the window is not visible and when the message is empty. No
      burning a core to animate nothing.
- [x] Driven by the Observation framework and `.animation(_:value:)` or `TimelineView` —
      not a `Timer` mutating state on a background queue, and not `DispatchQueue`.

---

## Task 3 — Revisit `columnsPerRevolution` (D12 said to, once scrolling existed)

D12 fixed 180 and explicitly deferred the question until scrolling landed, because a scroll
window changes the trade between letter size and dark arc. D14 then ruled out adopting the
sibling's 142.

**Acceptance**
- [x] A recommendation to the architect, with screenshots at two or three candidate values,
      on whether 180 is still right now that long messages scroll.
- [x] Do not change the value unilaterally — D12 and D14 are architect decisions. Report.

---

## Task 4 — Persistence for the eight slots

Per-slot drafts currently live only in memory.

**Acceptance**
- [x] All eight slots survive relaunch, including which slot was selected.
- [x] Behind a protocol, injected with a production default, per the standing DI rule. The
      ViewModel must not know whether it is talking to a file, `UserDefaults`, or a test
      double.
- [x] A test double proves the ViewModel saves and restores without touching the disk.
- [x] Corrupt or absent stored data yields empty slots, never a crash and never a trap.
- [x] The app is sandboxed — write inside the container. No new dependencies.

---

## Task 5 — Close D4

D4 said `GlyphFont.supportedCharacters` was kept for one slice on condition it earned its
place as an unsupported-character hint, and slice 4 reported shipping that caption.

**Acceptance**
- [x] Confirm the hint exists and works, or delete the property. Either outcome closes D4 —
      state which in the report.

---

## Task 6 — Leave it finished

**Acceptance**
- [x] `docs/current-state.md` describes the finished app, not a draft: what works, what is
      blocked and why, and where the hardware investigation stands.
- [x] `docs/brief.md` Milestones updated — including the stale "send frames" wording, which
      D5 superseded with messages in slots.
- [x] `features.md` boxes ticked only where demonstrable. The F5 box that needs a message on
      the blades stays open, and should say why in one line.
- [x] `README.md` reading order still makes sense for someone arriving cold.

---

## Evidence

A screenshot cannot show scrolling. Capture a short screen recording or a strip of frames
at successive offsets, and put it in `docs/reports/images/`. The standing rule in this
project is that the acceptance box is not ticked by the code compiling — it is ticked by
something a person can look at.

## Out of scope

- Anything touching the fan, the protocol, or `vendor/`.
- New third-party dependencies.
- Image or animation upload, brightness control, multiple fonts.

## Definition of done

1. Builds with no warnings; all tests pass.
2. Every box above ticked only where demonstrable; `features.md` updated.
3. Recording or frame strip of scrolling, in both appearances.
4. Acceptance report at `docs/reports/2026-09-03-slice-7-*.md`, with the usual section on
   where this brief was wrong.
5. Everything committed.

## Note

This is intended to be the last scheduled slice. If it lands, LedFan is a finished,
tested, documented macOS app whose only missing capability is one no amount of Swift can
supply. That is a good place to stop, and the docs should read like a project that
chose to stop rather than one that ran out.
