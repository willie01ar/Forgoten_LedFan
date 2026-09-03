# Current state

## The finished app (2026-09-03)

LedFan is a sandboxed macOS app, Swift 6 with strict concurrency complete, zero
third-party dependencies, zero build warnings, 88 unit tests and 8 UI tests passing, plus
2 hardware-checklist UI tests that skip unless a flag and the fan are present.

**What it does.** You type a message into one of eight slots, up to 26 characters, and see
it rendered as the fan would paint it: a polar preview at a fixed angular resolution, glyph
tops at the rim, short messages centred on the top of the disc, messages longer than a
revolution scrolling as a marquee with a dark gap before they wrap. Characters with no
glyph are named in a caption and drawn blank. Over-length drafts are refused visibly and
never cut. The eight drafts and the selected slot survive relaunch. The simulated fan
stores messages per slot and confirms with a time-stamped line. The USB fan connects,
reports itself, and states plainly that the message format the app implements belongs to a
different generation of fan; Send writes the table anyway, logs the exact packets, and
reports "no acknowledgement", never success.

**What is blocked, and why.** Sending a message to the physical fan. The head is a
write-only HID device on the rotating hub whose stored-table format was never found: every
free route was exhausted over twelve cable swaps, a blind sweep erased the factory demo,
and the vendor editor that was found targets a sibling product. The app writes the only
format it has, the generation-2 table (D16), knowing the head ignores it. This is not a
software problem. What would reopen it is at the
end of `protocol-findings.md`.

**Where the hardware investigation stands.** Stalled, not closed, in the architect's
words: it needs the software that shipped with a `0c45:7701` fan, a USB capture of it, or
a second unit. `protocol-discovery.md` records every route and its status;
`protocol-findings.md` is the complete log.

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
    EEPROMWriter.swift          EEPROMWriting (D8): 24C16 block addressing, six data bytes per report
    GenerationTwoTableSerializer.swift  MessageTableSerializing + the 0c45:7160 family's table, byte for byte (D16)
    FanTableWriter.swift        serializer -> EEPROM reports, no I/O; PacketLog writes each send to a file
    HIDFanTransport.swift       actor over IOHIDDevice; connects, writes the table, returns a receipt, never reads (D16)
    SimulatedFanTransport.swift actor holding messages per slot; storedMessages stream is a test seam
    DefaultFanTransportProvider.swift  production wiring of kind -> transport
    MessageStoring.swift        SavedDrafts + the persistence protocol; normalises malformed data
  Persistence/
    FileMessageStore.swift      JSON in Application Support inside the container; TransientMessageStore for previews and UI tests
  Presentation/
    FanConnectionStatus.swift   connection state enum
    FanMessageViewModel.swift   @MainActor @Observable; slots, counter, scrolling, restore/save
    ContentView.swift           dumb view; ScrollingPreview drives a TimelineView, paused for Reduce Motion or an inactive scene
    FanSimulatorView.swift      Canvas polar plot
    LaunchOptions.swift         -columnsPerRevolution and -transientStore, for evidence and UI tests only
  DesignSystem/
    Theme.swift                 Layout, Palette and Motion tokens

LedFanTests/                    Swift Testing
    MessageRasterizerTests.swift
    FrameComposerTests.swift         invariant, arc, offset, wrap, orientation
    FanMessageTests.swift            slot and length validation
    EEPROMWriterTests.swift          block addressing, padding, packet counts
    GenerationTwoTableSerializerTests.swift  byte-for-byte against the vendor stream
    FanTableWriterTests.swift        the seam with a trivial serializer; the packet log
    MessageStoreTests.swift          SavedDrafts normalisation, file store round trip, corrupt data
    FanTransportTests.swift          simulated transport, hardware refusal, error copy
    FanMessageViewModelTests.swift   RecordingTransport and RecordingMessageStore doubles; scrolling; persistence

LedFanUITests/                  XCTest, because XCUIApplication requires it
    LedFanUITests.swift              Milestone 1 flow, slots, over-length refusal, scroll frame strips, candidate widths
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

## Known limits

1. **The fan's stored-table format is unknown and the factory demo is erased.** The app
   writes the generation-2 table (D16), which this head ignores. A Version 3 format, if one
   is ever found, is one new `MessageTableSerializing` conformance.
2. **`HIDFanTransport.placeholderGeometry`** (11 LEDs, 180 columns) is a preview guess.
3. **At 180 columns per revolution, no message scrolls.** The longest allowed message is
   26 characters, 156 columns at the rasterizer's 6-column pitch, which fits one revolution.
   Scrolling is implemented, tested, and demonstrated at narrower widths through
   `-columnsPerRevolution`; whether the shipped width should change is the architect's
   call (D12, D14, slice 7 report).
4. **Persistence is per user, not per fan.** Drafts live in the app's container; nothing is
   read back from a head, because nothing can be.

## Deliberate design decisions worth preserving

- The default injected transport is **simulated**, not HID, so the app runs with no hardware.
  The ViewModel depends on `FanTransportProviding`, never on a concrete transport; the
  picker in the UI switches kinds, and switching disconnects the previous transport.
- `IOHIDManagerOpen` is never called. Opening the manager before the device leaves report
  transfers failing with `kIOReturnNotOpen` on this fan.
- The transport's unit of work is a `FanMessage` in a slot (D5). Frames, strips and
  angular resolution are preview-only concerns; nothing above the transport knows the wire.
- The table format is confined to one type, `GenerationTwoTableSerializer`, behind
  `MessageTableSerializing`; the framing, `EEPROMWriter`, is separate and fully tested.
  `FanTableWriter` joins them with no I/O, so any format can be driven through the whole
  chain in tests.
- `HIDFanTransport` is deliberately thin. It connects, sends the writer's reports, never
  reads (this head never answers), logs every send, and returns a receipt in plain words.
- Drafts are saved through `MessageStoring`, injected with a file store by default and a
  transient store for previews and UI tests. The ViewModel never knows which.
- Scrolling is a `TimelineView` reading a pure `previewFrame(at:)` from the ViewModel. No
  timer object, nothing mutates on a tick, and the view pauses it for Reduce Motion, an
  inactive scene, or a message with nothing to scroll.
