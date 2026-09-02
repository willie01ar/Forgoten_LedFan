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
    func store(_ message: FanMessage) async throws
    func disconnect() async
}

nonisolated protocol MessageRasterizing: Sendable {
    func strip(for text: String, ledsPerArm: Int) -> ColumnStrip
}

nonisolated protocol FrameComposing: Sendable {
    func frame(from strip: ColumnStrip, geometry: FanGeometry, columnOffset: Int) -> POVFrame
}

/// KNOWN. A0, address, up to six data bytes per 8-byte report.
nonisolated protocol EEPROMWriting: Sendable {
    func packets(writing bytes: [UInt8], toAddress address: UInt8) -> [[UInt8]]
}

/// UNKNOWN. The table the display firmware parses.
nonisolated protocol MessageTableSerializing: Sendable {
    func bytes(for messages: [FanMessage]) throws -> [UInt8]
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

## Where the unknown lives

The wire protocol is unknown, and that uncertainty is confined to **exactly one type**:
the `MessageTableSerializing` conformance, `UnknownMessageTableSerializer`, which throws
`.protocolNotYetKnown`. `EEPROMWriting` is known and tested. When the table format is
discovered, only the serializer changes. If a protocol discovery forces edits in the
ViewModel, the rasterizer, or the views, the boundary was drawn wrong.

`HIDFanTransport` owns the device handle. It connects and reports geometry, and it does
**not** write: there is deliberately no `IOHIDDeviceSetReport` in the app target (D9). The
transport tells the ViewModel so through `storeAvailability`, and the ViewModel keeps Send
disabled rather than enabled-then-failing.

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
     transportKind: FanTransportKind = .simulated)
```

Note the default is the **simulated** transport, not the HID one. The app must be runnable
and demoable with no hardware attached. Selecting the real transport is an explicit act.

## Module layout

```
LedFan/
  Domain/        FanGeometry (+ColumnStrip), POVFrame, FrameComposer, FanMessage, GlyphFont,
                 MessageRasterizer, FanDisplayTransport, FanTransportProviding
  Transport/     EEPROMWriter, MessageTableSerializer, HIDFanTransport, SimulatedFanTransport,
                 DefaultFanTransportProvider
  Presentation/  FanMessageViewModel, FanConnectionStatus, ContentView, FanSimulatorView
  DesignSystem/  Layout and Palette tokens
```

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77), so files
added under `LedFan/` join the target automatically. `Tools/` at the repository root sits
outside the group and is never compiled into the app — that is where throwaway probes live.
