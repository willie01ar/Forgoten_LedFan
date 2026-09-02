# Testing

Swift Testing (`import Testing`, `@Test`, `#expect`). Not XCTest.

## Principle

**No test may require the fan.** The hardware is one person's desk ornament with an unknown
protocol; a suite that depends on it is a suite that never runs. Everything above the
transport boundary is tested against protocol mocks.

Hardware verification is a manual checklist, kept separate and honest about being manual.

## What must be covered

### Rasterizer — pure, so test it hard
- Empty string, `ledsPerArm == 0`, single glyph, multiple glyphs.
- Column count equals `glyphWidth + letterSpacing` per character.
- Vertical centring: with 11 LEDs and a 7-row glyph the offset is 2, so a known glyph's
  first column is the font byte shifted left by 2.
- Masking: with 7 LEDs no column exceeds `0x7F`.
- Case insensitivity: `"a"` and `"A"` produce identical frames.
- Unsupported characters (emoji, control characters) produce blank columns.

### Packet encoder
- Every emitted packet is exactly 8 bytes.
- Packet count matches the column count and packing density.
- Sequence numbering is correct across packets.
- An empty frame is rejected rather than emitting a meaningless packet.

### Transports
- `display(_:)` before `connect()` throws `.notConnected`.
- `connect()` then `display(_:)` succeeds.
- `disconnect()` on a never-connected transport does not trap.

`HIDFanTransport` is **not** unit tested — it is a thin adapter over IOKit and there is
nothing to assert without the device. Keep it thin enough that this is true. If it grows
logic worth testing, that logic belongs in the encoder instead.

### ViewModel — via a recording mock
Provide a `RecordingTransport` actor conforming to `FanDisplayTransport` that captures
frames and can be configured to fail on connect.

- Editing `message` refreshes `previewFrame`.
- `sendMessage()` while disconnected sends nothing.
- `connect()` then `sendMessage()` delivers exactly one frame.
- A failing `connect()` leaves status non-connected and surfaces the reason.
- Tests are `@MainActor` because the ViewModel is.

## Manual hardware checklist

Needs the device, so it never runs by default. `LedFanUITests/HardwareChecklistUITests`
drives the app through it and skips unless `LEDFAN_HARDWARE` is set:

```bash
TEST_RUNNER_LEDFAN_HARDWARE=attached xcodebuild -project LedFan.xcodeproj -scheme LedFan -destination 'platform=macOS' -only-testing:LedFanUITests/HardwareChecklistUITests test
```

Use `=absent` with the data cable unplugged for the missing-device path. The last item
below is still a human's job.

- [ ] Data cable in the fan's **second** port, not just the power cable.
- [ ] `ioreg -c IOUSBHostDevice -r -w0 | grep -i sonix` shows the device.
- [ ] App connects and reports Connected.
- [ ] Send does not error.
- [ ] Something visibly changes on the fan. **This is the only test that matters for F5**
      — a successful `IOHIDDeviceSetReport` proves the write was accepted by the OS, not
      that the fan understood it.

## Standing trap

The last point generalises, and it is the lesson of this project's hardware phase: a
successful call is not a working feature. Verify at the output, not at the API.
