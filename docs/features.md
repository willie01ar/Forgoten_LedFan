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
- [x] Characters with no glyph render as blank rather than crashing or being dropped.
- [x] Lowercase input renders identically to uppercase.
- [x] An empty message produces an empty frame, not a crash.

---

## F2 — Text rasterisation

Convert a string into `POVFrame` columns.

**Contract:** `MessageRasterizing.frame(for:ledsPerArm:)`, pure and synchronous.

**Acceptance**
- [x] 5×7 column font, bit 0 at the top of each glyph column.
- [x] Glyphs are centred vertically for the given arm length.
- [x] Columns are masked to `ledsPerArm`; no bit is ever set above the arm length.
- [x] Configurable inter-letter spacing, default 1 column.
- [x] `ledsPerArm == 0` yields an empty frame rather than dividing by zero.
- [x] Pure function: same input, same output, no I/O, no global state.

---

## F3 — Simulated transport

The app must be fully usable and demoable with no hardware attached.

**Acceptance**
- [x] `SimulatedFanTransport` conforms to `FanDisplayTransport` and is the default injected
      transport.
- [x] `display(_:)` before `connect()` throws `.notConnected`.
- [x] Frames sent to it are observable, so the UI and tests can both consume them.
      (Tests consume `frames`; the UI does not yet — see `current-state.md`.)

---

## F4 — Hardware connection

**Acceptance**
- [ ] Matches on `0x0C45:0x7701` via `IOHIDManager`.
- [x] Absent device produces `.deviceNotFound` with a message naming the two-port trap —
      the user's most likely mistake is the power cable. (Message and code path exist;
      not yet exercised against the device.)
- [x] Connection state is visible in the UI at all times.
- [ ] `disconnect()` closes the device and is safe to call when never connected.
- [ ] Repeated `connect()` calls are idempotent.

---

## F5 — Sending to hardware

**Acceptance**
- [x] Send is disabled unless connected.
- [x] Frames are encoded to 8-byte reports through `FanPacketEncoding` and written with
      `IOHIDDeviceSetReport`.
- [x] A write failure surfaces the IOKit code in a human-readable message; the app does not
      crash and does not silently swallow it. (Verified against a mock, not hardware.)
- [ ] **Blocked on the wire protocol.** Until it is known, this feature can be built,
      tested against a mock, and left unverified against hardware. Say so in the UI rather
      than implying success.

---

## F6 — Error surfacing

**Acceptance**
- [x] Every `FanTransportError` case has a `LocalizedError` description written for a
      person, not a developer.
- [x] Errors appear in the UI, not only in the console.
- [x] No `try?` that discards a failure the user should know about.

---

## Deferred

Brightness and scroll speed control; saved messages; image upload.
