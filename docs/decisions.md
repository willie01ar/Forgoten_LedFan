# Decision log

Architect decisions. Newest first. A decision here overrides anything older in the docs.

---

## D1 — Frames are a full revolution; angular resolution is fixed geometry
**2026-09-01. Answers slice-1 open question 1. Blocking for the encoder work.**

**Problem.** The preview divides 360° by the column count, so a short message spreads
across the whole circle. Slice-1 evidence shows "HELLO" as 30 columns at 12° apart —
unreadable spokes, not text. A real fan has a fixed number of columns per revolution.

**Decision.** Separate *rasterising a message* from *composing a revolution*.

```swift
nonisolated struct FanGeometry: Sendable, Equatable {
    let ledsPerArm: Int
    let columnsPerRevolution: Int
}

/// A message rendered to columns. Arbitrary length — may exceed one revolution.
nonisolated struct ColumnStrip: Sendable, Equatable {
    let ledsPerArm: Int
    let columns: [UInt16]
}

/// Exactly one revolution. `columns.count == geometry.columnsPerRevolution`, always.
nonisolated struct POVFrame: Sendable, Equatable {
    let geometry: FanGeometry
    let columns: [UInt16]
}

nonisolated protocol MessageRasterizing: Sendable {
    func strip(for text: String, ledsPerArm: Int) -> ColumnStrip
}

nonisolated protocol FrameComposing: Sendable {
    func frame(from strip: ColumnStrip, geometry: FanGeometry, columnOffset: Int) -> POVFrame
}
```

`FanDisplayTransport` vends `var geometry: FanGeometry { get async }` instead of
`ledsPerArm`.

**Why this shape.** The composer pads a short strip to a full revolution and wraps a long
one, and `columnOffset` makes scrolling a parameter rather than a redesign — Milestone 3
becomes a timer incrementing an integer. It also keeps the rasterizer pure and unchanged in
character.

**Open value.** `columnsPerRevolution` for the real fan is unknown until the protocol is.
Use 180 for the simulated transport. Treat the HID transport's value as a placeholder and
say so in code. Do not let this number leak into the rasterizer.

---

## D2 — Transport selection: approved as proposed
**2026-09-01. Answers open question 2.**

`TransportKind` on the ViewModel, bound to a `Picker`, with construction behind an injected
factory protocol so the view never names a concrete transport. Ship it as proposed.

Default remains simulated. Selecting hardware stays an explicit act.

---

## D3 — The preview shows what will be sent, not what was sent
**2026-09-01. Answers open question 3.**

No second canvas. One preview, rendering the composed frame for the current message — it is
a preview, and labelling it as one is honest.

Delivery confirmation is a "Last sent HH:MM:SS" line, not a duplicate visualisation.

`SimulatedFanTransport.frames` stays. It is on the concrete type and not on the protocol,
so it is a test seam rather than dead UI code. That is a legitimate role; keep it and keep
its tests.

---

## D4 — Keep `supportedCharacters`, but use it or lose it
**2026-09-01. Answers open question 4.**

Keep it for one more slice and use it: a caption naming characters in the current message
that will render blank, so the user is not left wondering why part of their text vanished.
If the next slice ships without that hint, delete the property.
