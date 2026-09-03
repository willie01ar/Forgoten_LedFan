# Testing

Swift Testing (`import Testing`, `@Test`, `#expect`). Not XCTest.

## Principle

**No test may require the fan.** The hardware is one person's desk ornament with an unknown
protocol; a suite that depends on it is a suite that never runs. Everything above the
transport boundary is tested against protocol mocks.

Hardware verification is a manual checklist, kept separate and honest about being manual.

**No automated test may write to the head.** Not a unit test, not a UI test, not with a
flag. The head's table was erased by a blind write once; a test suite that can do that
again is a hazard, not a safety net. `HIDFanTransport` contains no report-writing call at
all (decisions.md D9), and the hardware checklist only connects, reads what the device
reports, and disconnects.

## What must be covered

### Rasterizer — pure, so test it hard
- Empty string, `ledsPerArm == 0`, single glyph, multiple glyphs.
- Column count equals `glyphWidth + letterSpacing` per character.
- Vertical centring: with 11 LEDs and a 7-row glyph the offset is 2, so a known glyph's
  first column is the font byte shifted left by 2.
- Masking: with 7 LEDs no column exceeds `0x7F`.
- Case insensitivity: `"a"` and `"A"` produce identical frames.
- Unsupported characters (emoji, control characters) produce blank columns.

### Frame composer — pure, so test it hard
- A frame always has exactly `columnsPerRevolution` columns, whatever the strip length.
- A short strip occupies a proportional arc; the rest of the revolution is dark.
- `columnOffset` shifts the strip around the disc; a full revolution is the identity;
  negative offsets wrap.
- A strip longer than a revolution shows a window and wraps.
- Glyph tops land on the outer LED.

### Message
- 26 characters fit; the 27th is refused with the excess count. Slots outside 0..<8 are
  refused. Characters count as a person counts them.

### EEPROM writer (the known half of the encoder)
- Every packet is exactly 8 bytes and starts with `A0`.
- The address advances by each packet's payload length; the final chunk is zero padded.
- A 26-byte payload needs five packets; nothing to write emits nothing.
- The stall-prone range `0x18…0x23` is the one the firmware showed.

### Message table serializer (the unknown half)
- The single conformance throws `.protocolNotYetKnown`.

### Scrolling — pure, so test it hard
- A message that fits one revolution never scrolls; an empty one never scrolls.
- A longer message advances `Motion.scrollColumnsPerSecond` columns per second, wraps
  through the gap, and returns to its start after one full period.
- A nil date yields the static frame (Reduce Motion, inactive scene).

### Persistence
- `SavedDrafts` pads, trims and clamps anything malformed, including when decoding.
- `FileMessageStore`: absent data is nil, corrupt data is nil, saves round-trip and
  overwrite, all in a temporary directory.
- The ViewModel restores every slot and the selection, saves every edit, and surfaces a
  failed save as an error, all against a recording double that never touches the disk.

### Transports
- `store(_:)` before `connect()` throws `.notConnected`.
- `connect()` then `store(_:)` succeeds and is retained per slot.
- `disconnect()` on a never-connected transport does not trap.
- The hardware transport reports that it cannot store, in copy that does not blame the
  user's setup.

`HIDFanTransport` is **not** unit tested — it is a thin adapter over IOKit and there is
nothing to assert without the device. Keep it thin enough that this is true. If it grows
logic worth testing, that logic belongs in the encoder instead.

### ViewModel — via a recording mock
Provide a `RecordingTransport` actor conforming to `FanDisplayTransport` that captures
messages and can be configured to fail on connect, fail on store, or refuse to store.

- Editing `message` refreshes `previewFrame`; a short message is centred on the top.
- Each slot keeps its own draft.
- The counter tracks the limit; an over-length draft disables Send and is never cut.
- `sendMessage()` while disconnected sends nothing.
- `connect()` then `sendMessage()` stores exactly one message, in the selected slot.
- A failing `connect()` leaves status non-connected and surfaces the reason.
- A transport that cannot store disables Send and exposes its reason.
- Tests are `@MainActor` because the ViewModel is.

## UI tests

Every launch passes `-transientStore YES`, so the tests never read or write the real
container. Scrolling evidence is captured at `-columnsPerRevolution 120`, because at the
shipped 180 no message is longer than a revolution; the frames are composited into
`reports/images/2026-09-03-scroll-strip-*.png`.

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
- [ ] Send is disabled and the UI says the message format is not yet known.
- [ ] (When D9 is lifted) after a cable swap, something visibly changes on the fan. **This
      is the only test that matters for F5** — a successful write proves the OS accepted it,
      not that the fan understood it.

## Standing trap

The last point generalises, and it is the lesson of this project's hardware phase: a
successful call is not a working feature. Verify at the output, not at the API.
