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

The app under `LedFan/` builds warning-free in Swift 6 with strict concurrency, the unit
suites and the UI test pass, and Milestone 1 is demonstrated (2026-09-01). See
`current-state.md` for the inventory and `features.md` for which acceptance boxes are
ticked.

`Tools/HIDFan/hidfan.swift` has still never been compiled. Treat it as a draft.

## Next tasks, in order

1. **Read the end-of-day summary in `protocol-findings.md` before touching the fan.** The
   factory demo has been erased by probing; the head is dark until a valid table is
   written. The table format is unknown and is not the sibling fans' format.
2. **Route 1 is the only cheap route left:** the software that shipped with a
   `0c45:7701` fan. Nothing else found online applies to this product ID.
3. Blind probing costs the owner one cable swap per observation (the data port is on the
   rotating head). Batch experiments; do not spend swaps on single packets.
4. Feature-report writes need the owner's explicit consent. Not given as of 2026-09-01.
5. Milestone 3 polish only after the fan shows a message.

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
