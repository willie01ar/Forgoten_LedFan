# Features

Each feature states its contract and its acceptance criteria. Criteria are binding; a
feature is not done until every box is true and demonstrable.

---

## F1 — Message composition with live preview

Type a message and see, immediately, what the fan would paint.

**Acceptance**
- [x] Editing the text field updates the preview without an explicit action.
- [x] Preview renders in polar coordinates — columns swept around a circle, LEDs from hub
      to tip — because that is what the spinning arm actually draws.
- [x] Characters with no glyph render as blank rather than crashing or being dropped, and
      a caption names them (D4).
- [x] Lowercase renders with its own glyphs, descenders below the baseline (D18); characters
      with no glyph of their own fall back to their uppercase form, then to blank.
- [x] An empty message produces a blank frame, not a crash.
- [x] A 26-character message renders as recognisable text (D1; screenshots in
      `reports/images/2026-09-02-*`).
- [x] A short message occupies a proportional arc centred on the top; the remainder is dark.
- [x] `columnOffset` shifts the message around the disc (proven by `FrameComposerTests`).
- [x] A message longer than one revolution scrolls as a marquee and wraps through a dark gap,
      never a seam (`reports/images/2026-09-03-scroll-strip-*.png`).
- [x] A message that fits one revolution stands still, centred on the top. There is nothing
      to scroll, and a still frame is easier to judge.
- [x] Reduce Motion stops the scroll and shows the static frame. The redraw also pauses
      when the scene is inactive or the message is empty.

---

## F2 — Text rasterisation and composition

Convert a string into a `ColumnStrip`, then compose one revolution.

**Contracts:** `MessageRasterizing.strip(for:ledsPerArm:)` and
`FrameComposing.frame(from:geometry:columnOffset:)`, both pure and synchronous.

**Acceptance**
- [x] 5×7 column font, bit 0 at the top of each glyph column.
- [x] Glyphs are centred vertically for the given arm length.
- [x] Columns are masked to `ledsPerArm`; no bit is ever set above the arm length.
- [x] Configurable inter-letter spacing, default 1 column.
- [x] `ledsPerArm == 0` yields an empty strip rather than dividing by zero.
- [x] Pure functions: same input, same output, no I/O, no global state.
- [x] The rasterizer knows nothing about geometry; the composer owns angular resolution.
- [x] A frame always has exactly `columnsPerRevolution` columns.

---

## F3 — Simulated transport

The app must be fully usable and demoable with no hardware attached.

**Acceptance**
- [x] `SimulatedFanTransport` conforms to `FanDisplayTransport` and is the default injected
      transport.
- [x] `store(_:)` before `connect()` throws `.notConnected`.
- [x] Stored messages are retained per slot and observable through `storedMessages`, a test
      seam on the concrete type (D3).

---

## F7 — Messages live in slots

`FanMessage { slot, text }`, `maximumCharacters = 26`, `slotCount = 8` (D5).

**Acceptance**
- [x] Slot picker, 1–8, in the controls card.
- [x] Live character counter against the 26-character limit.
- [x] Over-length input is visibly refused: red counter, a caption naming the excess, Send
      disabled. The draft is never cut.
- [x] Validation lives in the domain type (`FanMessage.init` throws), not the view.
- [x] Per-slot drafts are retained in memory while the app runs; persistence is out of scope.
- [x] A successful store shows the transport's receipt after the time (D3).
- [x] Send publishes all eight slots and says so; an over-length draft in any slot blocks it
      and is named (D19).

---

## F4 — Hardware connection

**Acceptance**
- [x] Matches on `0x0C45:0x7701` via `IOHIDManager`. (Matching only; the manager is never
      opened — see `protocol-findings.md`.)
- [x] Absent device produces `.deviceNotFound` with a message naming the two-port trap —
      the user's most likely mistake is the power cable. (Demonstrated with the cable out via
      `HardwareChecklistUITests`, `LEDFAN_HARDWARE=absent`.)
- [x] Connection state is visible in the UI at all times.
- [x] `disconnect()` closes the device and is safe to call when never connected.
- [ ] Repeated `connect()` calls are idempotent. (Guarded in code; not yet demonstrated.)

---

## F5 — Sending to hardware

**Done. The fan shows what the app sends (2026-09-25, slice 9).**

**Acceptance**
- [x] Send is disabled unless connected, and disables by itself when the fan is unplugged;
      the copy says the fan was unplugged, not that the write failed (D21).
- [x] Every report's echo is verified; the receipt counts confirmed, differing and missing
      echoes and says plainly when all were confirmed (D20).
- [x] Selecting the hardware transport says which protocol Send uses and how to program
      the fan: data cable in, switched off, then swap to power to see the result.
- [x] The copy does not imply a fault in the user's setup, and a unit test asserts it
      contains no unqualified success language.
- [x] `GenerationTwoTableSerializer` implements the `0c45:7160` family's table byte for byte
      against the Slice 5 findings: count byte, `columns+2`, effect packing, characters last
      to first, little-endian columns, trailing zeros, the 2 KB ceiling refused rather than
      truncated. Pure, `nonisolated`, rasterising through the injected rasterizer.
- [x] `EEPROMWriting` frames the whole 2 KB store: eight blocks, `A0`…`AE` headers, no
      packet across a block boundary.
- [x] `PearlFanEncoder` reproduces pearlfan-rs's packet stream byte for byte for five
      reference inputs, including an empty slot, "A" and a full 26-character message
      (`PearlFanEncoderGoldenTests`). Effects use the reference codes; "remain" is the default.
- [x] `HIDFanTransport.store(_:)` sends the encoder's reports, opens the device seized as
      the reference does, waits one second per report for an interrupt-IN acknowledgement,
      logs each report with what came back, and returns a receipt in words.
- [x] `GenerationTwoTableSerializer` stays selectable through `FanTableWriter`, the same
      `FanReportEncoding` seam.
- [x] The seam holds: a trivial test-only serializer runs through the same writer unchanged.
- [x] A message stored on the hardware appears on the blades. `HELLO WILLIE`, slot 1,
      first send, "upright and readable" (`protocol-findings.md`, 2026-09-25).
- [x] A send defines the whole stored set: slots not sent are cleared, not preserved. The
      app currently sends one slot at a time; see the slice 9 report's open item.

---

## F8 — Drafts survive relaunch

`MessageStoring`, injected; `FileMessageStore` in the sandbox container by default.

**Acceptance**
- [x] All eight slots and the selected slot survive relaunch (`FileMessageStore` round trip
      and `restore()` tests).
- [x] The ViewModel does not know what is behind the protocol; a recording double proves
      saves and restores without touching the disk.
- [x] Corrupt or absent stored data yields empty slots, never a crash.
- [x] No new dependencies; JSON via Foundation.

---

## F6 — Error surfacing

**Acceptance**
- [x] Every `FanTransportError` and `FanMessageError` case has a `LocalizedError`
      description written for a person, not a developer.
- [x] Errors appear in the UI, not only in the console.
- [x] No `try?` that discards a failure the user should know about.

---

## Not planned

Brightness and scroll-speed controls; image upload; other fan models. See `brief.md`.
