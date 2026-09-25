# Architecture

Contract-level. Signatures and boundaries are binding; implementation is yours.

> **Superseded in part.** `decisions.md` D1 splits rasterising from composing a revolution
> and replaces `ledsPerArm` on the transport with `FanGeometry`. Read D1 before the
> contracts below.

## Layers

```
Presentation   @MainActor @Observable ViewModels, dumb SwiftUI views
     |          depends on protocols only, never on a concrete transport
Domain         pure Sendable value types + protocols. No I/O, no framework imports
     |          beyond Foundation. Fully testable without hardware.
Transport      actors performing I/O. One per channel: HID, simulated.
```

Dependencies point inward. Domain knows nothing about Transport or Presentation.

## Core contracts

These protocols are the architecture. Everything else is detail. Shapes per decisions
D1, D5 and D8.

```swift
nonisolated protocol FanDisplayTransport: Sendable {
    nonisolated var displayName: String { get }
    nonisolated var storeAvailability: FanStoreAvailability { get }   // .available / .unavailable(reason:)
    var geometry: FanGeometry { get async }

    func connect() async throws
    nonisolated var connectionEvents: AsyncStream<FanConnectionEvent> { get }   // .lost(reason:) when unplugged (D21)
    func store(_ messages: [FanMessage]) async throws -> FanStoreReceipt   // the whole set (D19); what happened, in words
    func disconnect() async
}

nonisolated protocol MessageRasterizing: Sendable {
    func strip(for text: String, ledsPerArm: Int) -> ColumnStrip
}

nonisolated protocol FrameComposing: Sendable {
    func frame(from strip: ColumnStrip, geometry: FanGeometry, columnOffset: Int) -> POVFrame
}

/// The seam every protocol implements: messages to the exact 8-byte reports sent.
nonisolated protocol FanReportEncoding: Sendable {
    func reports(for messages: [FanMessage]) throws -> [[UInt8]]
}

/// Generation-2 only. Framing: 24C16 block addressing, up to six data bytes per 8-byte report.
nonisolated protocol EEPROMWriting: Sendable {
    func packets(writing bytes: [UInt8], toAddress address: UInt16) -> [[UInt8]]
}

/// The table the display firmware parses. One conformance ships: the generation-2 family's.
nonisolated protocol MessageTableSerializing: Sendable {
    func bytes(for messages: [FanMessage]) throws -> [UInt8]
}

/// Where drafts live between launches. nil on load means absent or unreadable.
nonisolated protocol MessageStoring: Sendable {
    func load() async -> SavedDrafts?
    func save(_ drafts: SavedDrafts) async throws
}
```

The domain currencies:

```swift
struct FanMessage  { slot: Int (0..<8); text: String (<= 26 characters, validated in init) }
struct FanGeometry { ledsPerArm: Int; columnsPerRevolution: Int }
struct ColumnStrip { ledsPerArm: Int; columns: [UInt16] }        // a message, any length, bit 0 = glyph top
struct POVFrame    { geometry: FanGeometry; columns: [UInt16] }  // one revolution, count == columnsPerRevolution, bit 0 innermost
```

`POVFrame`, `FrameComposing` and `columnsPerRevolution` are **preview-only** (D5): they
describe what the screen draws, never what is sent. The composer centres short messages
on the top of the disc and mirrors columns so glyph tops sit at the rim.

## Where the protocol lives

Behind `FanReportEncoding`. `PearlFanEncoder` is this head's (`0c45:7701`, D17),
golden-tested against the reference driver; `FanTableWriter` is the generation-2 sibling's,
kept selectable. Adding a fan model is one conformance. If a new format forces edits in
the ViewModel, the rasterizer, or the views, the boundary was drawn wrong. Slice 9 proved
the seam the way D8 intended: the transport, ViewModel and views did not change when the
real protocol replaced the placeholder.

`HIDFanTransport` owns the device handle. It opens the device seized as the reference
driver does, sends the encoder's reports with `IOHIDDeviceSetReport`, waits one second per
report for the fan's echo through `InputReportInbox` (an actor fed by the IOKit callback
on the main run loop), verifies each echo (`EchoVerification`, D20), observes removal
through IOKit's removal callback and a `RemovalFlag` actor (D21), logs each report with its
reply, and returns a `FanStoreReceipt` with the confirmed count. It declares `storeAvailability = .experimental(caveat:)`; the ViewModel
shows the caveat, keeps Send enabled, and uses the receipt's words as the confirmation line.

## Concurrency model

- **Transports are actors.** They own device handles and serialise access naturally.
- **ViewModels are `@MainActor @Observable` classes.** Not `ObservableObject`.
- **Everything crossing an actor boundary is an immutable `Sendable` struct.** A view or
  ViewModel never hands a reference into a transport.
- No `DispatchQueue`. No completion handlers. No escaping closures for async work.
- No `@unchecked Sendable` without a comment justifying it.
- `SWIFT_VERSION` is currently `5.0` in the project and **must be raised to 6.0** with
  strict concurrency complete. `SWIFT_APPROACHABLE_CONCURRENCY` is already enabled.

IOKit HID calls are synchronous C. Keeping them inside the transport actor is correct;
they are short. If profiling ever shows them blocking, move them behind an
`AsyncStream`-fed serial executor rather than reaching for a queue.

## Dependency injection

Initializer injection with production defaults, so views stay clean:

```swift
init(transportProvider: any FanTransportProviding = DefaultFanTransportProvider(),
     rasterizer: any MessageRasterizing = ColumnRasterizer(),
     composer: any FrameComposing = RevolutionComposer(),
     messageStore: any MessageStoring = FileMessageStore(),
     previewGeometry: FanGeometry = .preview,
     transportKind: FanTransportKind = .simulated)
```

Note the default is the **simulated** transport, not the HID one. The app must be runnable
and demoable with no hardware attached. Selecting the real transport is an explicit act.

## Module layout

```
LedFan/
  Domain/        FanGeometry (+ColumnStrip), POVFrame, FrameComposer, FanMessage, GlyphFont,
                 MessageRasterizer, FanDisplayTransport, FanTransportProviding, MessageStoring
  Transport/     EEPROMWriter, MessageTableSerializer, HIDFanTransport, SimulatedFanTransport,
                 DefaultFanTransportProvider
  Persistence/   FileMessageStore, TransientMessageStore
  Presentation/  FanMessageViewModel, FanConnectionStatus, ContentView, FanSimulatorView
  DesignSystem/  Layout and Palette tokens
```

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77), so files
added under `LedFan/` join the target automatically. `Tools/` at the repository root sits
outside the group and is never compiled into the app — that is where throwaway probes live.
