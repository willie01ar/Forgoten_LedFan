# Brief

## Goal

A macOS app where you type a message, see it rendered as the fan would paint it, and send
it to the physical fan over USB.

## Constraints

- Swift 6, strict concurrency complete. SwiftUI only.
- macOS 26.5 deployment target, sandboxed app.
- Minimal third-party dependencies — currently zero, and it should stay that way.
  Everything needed (IOKit HID, SwiftUI, Observation, Swift Testing) is in the SDK.
- MVVM with `@Observable` ViewModels; business logic in domain services, not ViewModels.
- Protocol-based dependency injection, initializer-injected with production defaults.

## What done looks like

**Milestone 1 — the app is real without the hardware.** Done (slice 1, 2026-09-01).
Type a message, watch the polar preview update live, store it on the simulated transport,
full unit test coverage of the domain. No USB required.

**Milestone 2 — the app talks to the fan.** Done (slice 9 and 10, 2026-09-25). The app
connects to `0x0C45:0x7701`, publishes the filled messages as PearlFan-protocol images (D17,
D22), verifies the fan's echo of every report (D20), and the fan displays them.
The protocol came from the public pearlfan-rs driver after the original head was destroyed
and a replacement with the same PID was bought; see `protocol-findings.md`, 2026-09-22 on.

**Milestone 3 — finishing.** Done (slice 7, 2026-09-03). Scrolling for messages longer
than a revolution, with Reduce Motion respected; the eight slots persist between
launches; a legible preview at a fixed angular resolution. Brightness and scroll-speed
controls were dropped: the preview is the only place they could act, and the fan's own
software has neither.

## Explicitly out of scope for now

- Image or animation upload. Text first.
- Brightness and scroll-speed controls (see Milestone 3).
- Supporting other fan models. One device, well.
- Any DriverKit extension. The device binds to Apple's generic HID driver; if a design
  seems to need a dext, that design is wrong.
