# Decision log

Architect decisions. Newest first. A decision here overrides anything older in the docs.

---

## D12 — `columnsPerRevolution` stays 180, and gets revisited with scrolling
**2026-09-02. Answers slice-4 open question 3.**

Keep 180. A 26-character message spans 312°, leaving little dark arc, and the lower half
reads rotated — but the preview's job is to let you judge your message, and letter size is
what makes that possible. Shrinking the glyphs to buy dark space is the wrong trade.

Revisit when scrolling lands. A scroll window shows part of the strip at a time, which
changes this trade completely — so do not tune it further now. The number is preview-only
(D5) and makes no claim about hardware.

---

## D11 — Glyph orientation is the composer's job
**2026-09-02. Answers slice-4 open question 2. Approved as implemented.**

Strip bit 0 is the glyph top; frame bit 0 is the innermost LED. Upright text on the upper
arc therefore needs the glyph top at the rim, which means a mirror somewhere.

Putting it in `RevolutionComposer` is right: the composer is the only layer that knows
about geometry and orientation, and the alternative — flipping the rasterizer's bit order —
would break the F2 contract and its tests for a reason that has nothing to do with
rasterising.

**Do not "fix" this later.** It looks like an inversion bug and is not. It is recorded here
so a future session does not helpfully remove it.

Caveat: this is the *preview's* orientation rule. Which way a real fan paints its glyphs is
a hardware fact nobody has yet. When the table format arrives, expect to discover the
device disagrees, and change the composer — not the rasterizer.

---

## D10 — `storeAvailability` joins the transport contract
**2026-09-02. Answers slice-4 open question 1. Approved.**

```swift
nonisolated var storeAvailability: FanStoreAvailability { get }
```

Task 5 requires Send to be *disabled* rather than enabled-then-failing, and the ViewModel
must not know which concrete transport can write. Without this property the only ways to
satisfy both are type-checking the transport in the ViewModel or letting the view special-
case the hardware case — each defeating the boundary the protocol exists to draw.

One property, carrying its own user-facing reason, is proportionate.

**One note for later.** The reason is currently a string, and there is a unit test asserting
its copy does not mention the cable. That test is doing real work — the copy is a promise to
the user that this is our gap, not their setup — but a domain type carrying presentation
copy is a smell that only stays harmless while there is one case. If a second reason
appears, make `FanStoreAvailability` carry a typed reason and move the copy to the
presentation layer.

---

## D9 — The app never writes to the fan until the table format is known
**2026-09-02. Safety decision. Non-negotiable.**

Blind writes erased the factory demo. That was an acceptable cost in a *tools* session with
the owner present and consenting. It must never happen from the app.

`HIDFanTransport.store(_:)` throws `.protocolNotYetKnown` until a real table serialiser
exists. It connects, reports geometry, and refuses to write. Writing arbitrary bytes to the
head stays a `Tools/` activity, done deliberately, with the owner at the fan.

The UI must say this plainly when the hardware transport is selected — not fail silently,
and not imply a send succeeded.

---

## D8 — Split the encoder: known framing, unknown table
**2026-09-02. Refines the FanPacketEncoding seam.**

Slice 3 established the transport-level shape with real evidence: `A0 <addr> <data…>`,
consistent with a HID-to-I2C bridge writing a 24Cxx EEPROM at address `0xA0`. Only `A0`
headers ever show write timing. That part is **known**.

What lives *in* the EEPROM — the table the display firmware parses — is unknown, and is not
the `0c45:7160` / `1a86:5537` sibling format.

Split the seam accordingly:

```swift
/// KNOWN. Frames an EEPROM write as 8-byte reports: A0, address, up to 6 data bytes.
nonisolated protocol EEPROMWriting: Sendable {
    func packets(writing bytes: [UInt8], toAddress address: UInt8) -> [[UInt8]]
}

/// UNKNOWN. Serialises the message table the display firmware parses.
nonisolated protocol MessageTableSerializing: Sendable {
    func bytes(for messages: [FanMessage]) throws -> [UInt8]
}
```

The first is testable today and should be fully unit tested — packet size, address
increment, six-byte payload chunking, the 0x18–0x23 range noted as suspicious. The second
throws `.protocolNotYetKnown` and is the entire remaining unknown, now one type wide
instead of two concerns tangled together.

---

## D7 — Feature-report probing: declined for now
**2026-09-02. Answers slice-3 open question 2.**

**Decision: no.** Not a permanent no, but not a blind sweep.

The upside is weaker than it looks. Every GET_REPORT on this head returns the last SETUP
packet — the bridge has no feature-report handler at all. A device that does not implement
feature reads probably does not implement feature writes either.

The downside is worse than what we have already paid. The erased EEPROM is *data*, and
presumably rewritable once the format is known. Feature reports on a bridge chip are where
device configuration lives — I2C addressing mode, bus speed, or worse. Corrupting that is
not recoverable, and with no read path there is no way to even diagnose it.

Revisit only with a **specific hypothesis** about what a particular feature report does.
Never as a sweep.

---

## D6 — Milestone 2 is paused; the preview is now the product
**2026-09-02. Answers slice-3 open questions 1 and 3.**

**Milestone 2 is paused**, not abandoned. Every published lead is closed, there is no read
path, no live observation, and each experiment costs the owner a cable swap. Continuing to
guess has poor expected value.

The deliverable becomes Milestone 1 plus hardware connection and the transport picker: an
app that connects to the real fan, reports what it is, and is honest that it cannot yet
write to it.

**Correcting slice 3's open question 3.** The report suggests angular resolution "matters
less until the table format exists". The opposite is true. With Milestone 2 paused, the
preview *is* the entire visible product, and it currently renders "HELLO" as unreadable
spokes. **D1 is now the highest-priority engineering work in the project.**

---

## D5 — The transport's unit of work is a message in a slot, not a frame
**2026-09-01. Supersedes part of D1. Triggered by the 8 x 26-character capability finding.**

**Problem.** The fan stores 8 messages of 26 characters. A device with that model has a
font in firmware and probably accepts text. Our transport contract takes a `POVFrame` of
rasterised columns, which may be the wrong currency entirely — and we will not know which
until the protocol is cracked.

**Decision.** Do not bet on either. Make the transport's unit of work the domain concept,
and let the encoder decide how it reaches the wire.

```swift
nonisolated struct FanMessage: Sendable, Equatable {
    static let maximumCharacters = 26
    static let slotCount = 8

    let slot: Int        // 0..<slotCount
    let text: String     // <= maximumCharacters after validation
}

nonisolated protocol FanDisplayTransport: Sendable {
    nonisolated var displayName: String { get }
    var geometry: FanGeometry { get async }

    func connect() async throws
    func store(_ message: FanMessage) async throws
    func disconnect() async
}
```

`FanPacketEncoding` now takes a `FanMessage`. If the device turns out to want text, the
encoder emits characters. If it wants bitmaps, the encoder rasterises internally. Either
way nothing above the transport changes — which is the point of having isolated the unknown
there in the first place.

**Effect on D1.** D1 still stands, but `POVFrame`, `FrameComposing` and
`columnsPerRevolution` are now **preview-only concerns**. They describe what we draw on
screen, not what we send. That is a simplification: `columnsPerRevolution` can be whatever
makes the preview legible, with no claim about hardware.

**New constraints to enforce.** 26 characters is a real hard limit, not a guess. The text
field needs a character counter and validation, and the UI needs a slot picker (1-8).
Truncation must be visible, never silent.

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
