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

These three protocols are the architecture. Everything else is detail.

```swift
protocol FanDisplayTransport: Sendable {
    nonisolated var displayName: String { get }
    var ledsPerArm: Int { get async }

    func connect() async throws
    func display(_ frame: POVFrame) async throws
    func disconnect() async
}

protocol MessageRasterizing: Sendable {
    func frame(for text: String, ledsPerArm: Int) -> POVFrame
}

protocol FanPacketEncoding: Sendable {
    func packets(for frame: POVFrame) throws -> [[UInt8]]
}
```

`POVFrame` is the currency between layers: an immutable `Sendable` value type describing
one revolution as vertical LED columns, bit 0 innermost.

```swift
struct POVFrame: Sendable, Equatable {
    let ledsPerArm: Int
    let columns: [UInt16]
}
```

## Where the unknown lives

The wire protocol is unknown, and that uncertainty must be confined to **exactly one
type**: the `FanPacketEncoding` conformance. When the protocol is discovered, only that
type changes. If a protocol discovery forces edits in the ViewModel, the rasterizer, or the
views, the boundary was drawn wrong.

`HIDFanTransport` owns the device handle and the report plumbing. It does not know what the
bytes mean. `FanPacketEncoding` knows what the bytes mean and owns no I/O.

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
init(transport: any FanDisplayTransport = SimulatedFanTransport(),
     rasterizer: any MessageRasterizing = ColumnRasterizer())
```

Note the default is the **simulated** transport, not the HID one. The app must be runnable
and demoable with no hardware attached. Selecting the real transport is an explicit act.

## Module layout

```
LedFan/
  Domain/        POVFrame, GlyphFont, MessageRasterizer, FanDisplayTransport, errors
  Transport/     FanPacketEncoding, HIDFanTransport, SimulatedFanTransport
  Presentation/  FanMessageViewModel, FanConnectionStatus, ContentView, FanSimulatorView
  DesignSystem/  Layout and Palette tokens
```

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77), so files
added under `LedFan/` join the target automatically. `Tools/` at the repository root sits
outside the group and is never compiled into the app — that is where throwaway probes live.
