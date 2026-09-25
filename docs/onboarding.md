# Onboarding — start here

You are picking up LedFan: a macOS app that displays a typed message on a USB LED
persistence-of-vision fan.

Read this page, then `brief.md`, then the rest in the order `README.md` lists.

## Prerequisites

- macOS with Xcode 26 or later (project `objectVersion 77`, deployment target macOS 26.5)
- Scheme: `LedFan`. No scheme file is checked in; Xcode auto-creates it from the
  targets, and `xcodebuild -scheme LedFan` finds it. Only mark it Shared if you need to
  customise it.
- The physical fan is optional. Milestone 1 needs no hardware at all.

## Where things stand

Working, as of 2026-09-25. Read `current-state.md` first: it says what the app does and
how the hardware question was settled. The fan's protocol is implemented and verified on
the device; `protocol-findings.md` is the record.

## If you pick this up

1. Build and run the tests (commands below). Everything should be green with no warnings.
2. Read `decisions.md`. Every design choice that is not obvious from the code is there.
3. Do not touch the fan without reading `hardware.md` and the end of
   `protocol-findings.md`. Twelve cable swaps and an erased factory demo are recorded there,
   and the app writes only the generation-2 table, never probes (D16).
4. If new evidence about the message-table format arrives, the only type that changes is
   `UnknownMessageTableSerializer` (D8, D13).

## Commands

```bash
xcodebuild -project LedFan.xcodeproj -scheme LedFan -destination 'platform=macOS' build
xcodebuild -project LedFan.xcodeproj -scheme LedFan -destination 'platform=macOS' test
```

Check the fan is attached and enumerating:

```bash
ioreg -c IOUSBHostDevice -r -w0 | grep -iA4 sonix
```

Nothing there? The fan has two ports and the USB-A one is **power only**. See
`hardware.md` before concluding anything.

## Guardrails

- **Never trust a negative hardware result without a control device in the same run.** This
  project produced two false "the device isn't there" conclusions that had to be retracted.
  `Tools/usbdiff.sh` exists for exactly this.
- **A successful API call is not a working feature.** `IOHIDDeviceSetReport` returning
  success means macOS accepted the write, not that the fan understood it. Verify at the
  output.
- **Record negative results.** Append to `protocol-findings.md` (create it). Knowing which
  command bytes do nothing is as valuable as knowing which one works, and it is exactly
  what gets lost between sessions.
- Do not add third-party dependencies. Everything needed is in the SDK.
- Do not reach for a DriverKit extension. The device binds to Apple's generic HID driver;
  if a design seems to need a dext, the design is wrong.

## Definition of done for a work session

1. It builds with no warnings.
2. Tests pass.
3. Every acceptance checkbox you claim in `features.md` is actually demonstrable — tick
   them in the file as you go.
4. Anything you learned about the hardware is written into `hardware.md` or
   `protocol-findings.md`, not left in the session transcript.
5. A short acceptance report: what you completed, what you did not, what you discovered
   that the specification got wrong.

Point 5 matters most. These documents were written before a single line compiled — expect
to find things they got wrong, and say so plainly rather than working around them silently.
