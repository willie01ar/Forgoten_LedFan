# Decision log

Architect decisions. Newest first. A decision here overrides anything older in the docs.

---

## D21 — Handle device removal properly
**2026-09-25. Answers slice-9 open item 5. A bug, not a question.**

After a cable swap the app still reports "Connected" and the next Send fails with
`kIOReturnBadArgument`. The owner hit this on his second send. Observe removal (an
`IOHIDManager` removal callback), and treat `kIOReturnBadArgument` / not-open from
`SetReport` as a lost connection rather than a write failure. Status returns to disconnected,
Send disables, and the copy says the fan was unplugged — not that the write failed.

Fix this first in the next slice. It is the one thing that makes a working feature feel broken.

---

## D20 — Verify the echoes
**2026-09-25. Answers slice-9 open item 4.**

The head echoes every report back on the interrupt-IN endpoint, with the header's first byte
returned as `A1`. That is better than the acknowledgement we hoped for: it is a loopback, so
comparing each echo against what was sent turns it into a genuine end-to-end transfer check.

Do it. Count mismatches, surface the count in the `FanStoreReceipt`, and say plainly when
every report was confirmed. The reference driver does not do this; we can, and for a device
with no other feedback path it is worth having.

Do not abort a send on a mismatch — record it. A partial write is more diagnosable than an
aborted one.

---

## D19 — A Send writes all eight slots
**2026-09-25. Answers slice-9 open item 1.**

Slice 9 established a protocol fact: **a send defines the fan's whole stored set.** Unsent
slots are cleared, not preserved — which is why slots 2-8 of the factory demo vanished.

The app's model must match the device's. **Send writes all eight slots**, taking the eight
persisted drafts (slice 7) and sending empty ones as blank images. The UI says so: this
publishes everything, it does not append one message.

The alternative — one slot per send, with a warning — was rejected. It makes the destructive
behaviour a footnote the user reads once and forgets, and it leaves the app's mental model
disagreeing with the hardware's.

**Effects (open item 2) are deferred.** The header's open, close and before-close fields have
known codes; transcribe them into `protocol-findings.md` so they are not lost, and leave the
UI at reference defaults until someone asks for it. Not every capability needs a control.

---

## D18 — Add lowercase glyphs to `GlyphFont`
**2026-09-25. Prompted by the factory demo transcription.**

The device's own demo shows mixed case, so its firmware font has lowercase. Ours does not:
every character is uppercased before lookup, which would turn `Mom Pick me up @4P` into
`MOM PICK ME UP @4P`. For a product whose demo calls itself a *NOTE PAD*, that is a visible
loss of fidelity, not a rounding error.

**Decision.** Extend the 5x7 table with lowercase a-z. It is a data change to one type — no
contract moves, no architecture impact. Keep the uppercase fallback for any character still
missing a glyph.

Descenders (g j p q y) need rows below the baseline. The glyph box is 7 rows and the arm is
11 LEDs, so the composer's vertical centring has room; verify a descender renders below the
baseline of its neighbours rather than being clipped or shifted.

Not a blocker for slice 9 — it can land alongside or after. Say so in the report either way.

---

## D17 — Implement the PearlFan protocol, the real one for our head
**2026-09-22. Supersedes the "stalled" status of the hardware chapter.**

Public drivers exist for `0c45:7701` (see `protocol-findings.md`, 2026-09-22). Add a
`PearlFanProtocol`: a `MessageTableSerializing` conformance (or a sibling type, if the
per-image header-plus-39-packets shape doesn't fit that seam) that emits exactly the packet
stream pearlfan-rs sends. Make it the hardware transport's default, and keep
`GenerationTwoTableSerializer` as the documented alternative.

**Licensing is a hard rule.** Ventto/pearlfan is GPLv3, and nothing from it may be copied into
this repository. pearlfan-rs is MIT/Apache-2.0 and may be read. Reimplement from the protocol
facts and credit both projects in the README.

**Validate against the reference before touching the fan.** Our encoder's bytes must match
pearlfan-rs's bytes for the same input, byte for byte. Only then does anything go to the
head.

The interrupt-IN read after each packet is part of the reference protocol. Implement it with a
timeout. If acknowledgements start arriving once the framing is right, that's the live
oracle, so record it.

---

## D16 — The writer gets a real implementation, and D9 is relaxed
**2026-09-03. Owner's decision, at his request. Supersedes D9.**

D9 said the app never writes to the fan until the table format is known. It was right at the
time: blind writes had erased the factory demo, and a Send button that scribbles on an
EEPROM is not a feature. But the loss it protected against has already happened, the head
has been dark for two days, and the owner wants the writer to exist in shape even knowing it
will not light the disc.

**Decision.** Implement the write path end to end, using the generation-2 table format that
slice 5 recovered from the vendor serializer. Both layers of D8 become real:

- `MessageTableSerializing` gains `GenerationTwoTableSerializer`, a full implementation of
  the `0x7160` family's stream — a pure function over `[FanMessage]`, unit tested against
  the byte-level layout in `protocol-findings.md`.
- `EEPROMWriting` already frames `A0 <addr> <data…>` and is already tested. It stays.
- `HIDFanTransport.store(_:)` actually sends.

**This is expected not to display anything.** `0x7701` ignored this format in every
position and encoding tried. That is the point: the value is a correct, exercised, testable
writer, not a working fan.

**Guardrails that survive.**
1. **Honesty in the UI.** The hardware transport must state plainly that the format belongs
   to a different generation of fan and is not expected to produce a display. Never imply
   success because a write returned without error.
2. **No blind traffic.** The app emits well-formed tables only. Sweeps, walking bits and
   header probes stay in `Tools/`, run deliberately, with the owner present.
3. **No hang on silence.** Our head never acknowledges. The vendor protocol expects a 3-byte
   ack with status `0x80`; the transport must treat its absence as normal, not retry, not
   block, and not report failure.
4. **Inspectable.** A send must be reproducible after the fact — write the exact packet
   stream to a file, as `Tools/` already does.
5. **Feature reports stay off.** D7 is untouched.

**When a Version 3 format is found**, only `MessageTableSerializing` gains a new conformance.
Nothing above the transport changes. That has been the whole point of the seam since D8, and
this decision is what finally proves it carries weight.

---

## D15 — One final batch of guesses, then the hardware question is closed
**2026-09-02. Answers slice-5 open question 3, and corrects its premise.**

Slice 5 proposes deferring the "header bytes stored ahead of the stream" guess "until route
1b, where an EEPROM clip turns the same question into a measurement".

**Route 1b does not exist.** The head cannot be dismantled without breaking it, there is one
fan, and `protocol-discovery.md` has said so since before this slice. Deferring to 1b means
deferring forever, so the deferral has to be re-decided on its own merits.

**Decision.** One final batch, then stop. Not one guess per swap — the oracle is too
expensive for that. Assemble the two or three best remaining candidates in a single
programming session, written at *different* EEPROM base addresses so that if the parser
reads from a fixed base only one is live but any of them lighting the disc is informative:

1. Slice 5's variant: `[size class][len lo][len hi][00][00]` ahead of the sibling stream.
2. The 1c length hypothesis: `A0 <length>` followed by continuation packets.
3. The sibling stream at whatever base the `A0` stall range (0x18-0x23) suggests.

One swap. If the disc stays dark, the hardware path is closed for good and the project is
what it is: a working app with no reachable fan. Record that as an outcome, not a failure —
the analysis is sound and the device simply does not answer.

---

## D14 — `columnsPerRevolution` stays 180; 142 does not transfer
**2026-09-02. Answers slice-5 open question 2. D12 stands.**

`LedScrW11=142` is real, but it is the *sibling's* screen width, and it is inconsistent with
our head: ours holds **26 characters**, and at the family's 8-column glyph pitch 26
characters need ~208 columns. A 142-column screen cannot hold them. So either our head is a
wider variant or it uses a narrower pitch — and either way 142 is not our number.

Our own rasterizer uses a 6-column pitch (5-wide glyph plus 1 spacing), so a full 26-character
message is 156 columns, which D12 already tuned 180 against.

Keep 180. Record 142 in the findings as sibling evidence with the arithmetic above, so a
later session does not adopt it as a hardware fact about our fan.

---

## D13 — D5's premise is revised; its contract stands
**2026-09-02. Answers slice-5 open question 1. Approved as recommended.**

D5 hedged between "the fan holds a firmware font and takes characters" and "the host
rasterises and uploads columns". **The second is now established** for this product family:
the editor ships its own font tables, stores rasterised columns in its project file, and its
serializer emits columns. No character codes ever reach the fan.

**The hedge was worth having and is now spent.** Drop the firmware-font branch.

What does *not* change is the contract. `FanMessage { slot, text }` stays the transport's
unit of work: slot, count and text are real concepts in this table format, not
approximations. The future `MessageTableSerializing` conformance rasterises internally,
through the app's own `MessageRasterizing`, injected — which is exactly the arrangement D8
put in place, now with the ambiguity removed.

This is what isolating the unknown behind one protocol was for. A finding that overturned
the central assumption changes one type's implementation and no contract above it.

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

*How it ended (2026-09-25).* Relaxed by D16 for the wrong-generation table, then made moot
by D17: the real protocol turned out to be published, the app's first well-formed send
displayed `HELLO WILLIE` on the replacement head, and the rule this decision protected,
"no blind writes from the app", still holds because the app now emits only complete images.

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
