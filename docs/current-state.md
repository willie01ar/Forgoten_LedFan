# Current state

## Trust level

As of 2026-09-01 everything under `LedFan/` compiles in Swift 6 language mode with strict
concurrency complete, builds without warnings, and passes 34 unit tests plus one UI test.
The original draft was written without a toolchain; the compiled version differs from it
mainly in isolation annotations (see below).

`Tools/HIDFan/hidfan.swift` has still never been compiled.

The specification in these documents is authoritative. Where the code disagrees with the
documents, change the code.

## What exists

```
LedFan/
  Domain/
    POVFrame.swift              frame value type
    GlyphFont.swift             5x7 column font, ~55 glyphs. Data worth keeping.
    MessageRasterizer.swift     MessageRasterizing + ColumnRasterizer
    FanDisplayTransport.swift   transport protocol + FanTransportError
  Transport/
    FanPacketEncoding.swift     protocol + SequencedColumnEncoder (A GUESS — see below)
    HIDFanTransport.swift       actor over IOHIDManager
    SimulatedFanTransport.swift actor vending frames via AsyncStream
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

Tools/                          throwaway probes, outside the app target
    probe-output/               raw ioreg/HID captures from the hardware investigation
    usbdiff.sh                  differential ioreg snapshot around a hotplug
    hidprobe.sh                 interface classes, endpoints, report descriptor
    HIDFan/hidfan.swift         interactive HID probe. Also never compiled.
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

1. **`SequencedColumnEncoder` is a guess.** It packs a sequence byte plus three big-endian
   columns per report. There is no evidence the fan understands this. It exists to make the
   boundary concrete and to give the tests something to assert against — not because it is
   believed correct. Replacing it is the whole of `protocol-discovery.md`.
2. **The UI cannot select the HID transport.** `FanMessageViewModel` defaults to the
   simulated transport and nothing in the UI swaps it. Milestone 2 needs that switch.
3. **The UI does not consume `SimulatedFanTransport.frames`.** The stream exists and is
   tested; the preview shows the rasterised message, not what was last sent.

## Deliberate design decisions worth preserving

- The default injected transport is **simulated**, not HID, so the app runs with no hardware.
- The unknown protocol is confined to one type. Keep it that way.
- `HIDFanTransport` is deliberately thin and untested; the logic worth testing lives in the
  encoder.
