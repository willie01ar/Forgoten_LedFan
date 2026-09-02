# Current state

## Trust level

As of 2026-09-01 everything under `LedFan/` compiles in Swift 6 language mode with strict
concurrency complete, builds without warnings, and passes 40 unit tests, 2 UI tests, and 2 hardware checklist tests that skip without the device.
The original draft was written without a toolchain; the compiled version differs from it
mainly in isolation annotations (see below).

The specification in these documents is authoritative. Where the code disagrees with the
documents, change the code.

## What exists

```
LedFan/
  Domain/
    FanGeometry.swift           FanGeometry + ColumnStrip (D1)
    POVFrame.swift              one revolution; count always == columnsPerRevolution
    FrameComposer.swift         FrameComposing + RevolutionComposer (padding, wrapping, offset, mirroring)
    FanMessage.swift            slot + text with the fan's limits; validation in init (D5)
    GlyphFont.swift             5x7 column font, ~55 glyphs. Data worth keeping.
    MessageRasterizer.swift     MessageRasterizing + ColumnRasterizer, geometry-free
    FanDisplayTransport.swift   transport protocol (geometry, store, storeAvailability) + FanTransportError
    FanTransportProviding.swift FanTransportKind, the provider protocol, FixedTransportProvider
  Transport/
    EEPROMWriter.swift          EEPROMWriting (KNOWN, D8): A0, address, six data bytes per report
    MessageTableSerializer.swift MessageTableSerializing (UNKNOWN, D8): the one type that throws .protocolNotYetKnown
    HIDFanTransport.swift       actor over IOHIDDevice; connects, reports geometry, never writes (D9)
    SimulatedFanTransport.swift actor holding messages per slot; storedMessages stream is a test seam
    DefaultFanTransportProvider.swift  production wiring of kind -> transport
  Presentation/
    FanConnectionStatus.swift   connection state enum
    FanMessageViewModel.swift   @MainActor @Observable
    ContentView.swift           dumb view
    FanSimulatorView.swift      Canvas polar plot
  DesignSystem/
    Theme.swift                 Layout and Palette tokens

LedFanTests/                    Swift Testing
    MessageRasterizerTests.swift
    FanTransportTests.swift          simulated transport, encoder, error copy
    FanMessageViewModelTests.swift   includes a RecordingTransport mock

LedFanUITests/                  XCTest, because XCUIApplication requires it
    LedFanUITests.swift              Milestone 1 flow: type, connect, send, disconnect
    HardwareChecklistUITests.swift   docs/testing.md manual checklist; skipped unless LEDFAN_HARDWARE is set

Tools/                          throwaway probes, outside the app target
    probe-output/               raw ioreg/HID captures from the hardware investigation
    usbdiff.sh                  differential ioreg snapshot around a hotplug
    hidprobe.sh                 interface classes, endpoints, report descriptor
    HIDFan/hidfan.swift         HID probe: REPL, listen, feature, sweep, bits. Compiles; see build.sh.
    HIDFan/*.py                 hidapi probes (sweeps, fills, stream writes). See HIDFan/README.md.
    BLEProbe/                   CoreBluetooth scanner. Moot — the fan is USB HID.

```

## Build settings that matter

- `SWIFT_VERSION = 6.0` and `SWIFT_STRICT_CONCURRENCY = complete` on all three targets.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target. Everything is main-actor
  by default, so the Domain types and protocols and the packet encoder are declared
  `nonisolated` explicitly. Forgetting that on a new domain type makes transport actors
  hop to the main actor to call it.
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`. A file that touches
  `localizedDescription` (or any Foundation member) must `import Foundation` itself.
- The USB entitlement comes from `ENABLE_RESOURCE_ACCESS_USB = YES`, the build-setting
  form of Signing & Capabilities → App Sandbox → Hardware → USB. There is no
  `.entitlements` file; the signed bundle carries `com.apple.security.device.usb`.

## Known problems

1. **The fan's stored-table format is unknown and the factory demo is erased.** See the
   end-of-day summary in `protocol-findings.md`. `UnknownMessageTableSerializer` is the
   placeholder; `EEPROMWriter` already frames whatever it will produce as `A0 <addr>
   <data>` packets. Milestone 2 is paused (D6) and the app never writes to the head (D9).
2. **`HIDFanTransport.placeholderGeometry`** (11 LEDs, 180 columns) is a guess used only
   for the preview; the real column count is unknown.
3. **No scroll animation yet.** `columnOffset` is a tested parameter; Milestone 3 drives it
   from a timer.

## Deliberate design decisions worth preserving

- The default injected transport is **simulated**, not HID, so the app runs with no hardware.
  The ViewModel depends on `FanTransportProviding`, never on a concrete transport; the
  picker in the UI switches kinds, and switching disconnects the previous transport.
- `IOHIDManagerOpen` is never called. Opening the manager before the device leaves report
  transfers failing with `kIOReturnNotOpen` on this fan.
- The transport's unit of work is a `FanMessage` in a slot (D5). Frames, strips and
  angular resolution are preview-only concerns; nothing above the transport knows the wire.
- The unknown protocol is confined to one type, `UnknownMessageTableSerializer`. Keep it
  that way. The known framing, `EEPROMWriter`, is fully tested.
- `HIDFanTransport` is deliberately thin. It connects, reports geometry and refuses to
  store; it contains no report-writing call at all (D9).
