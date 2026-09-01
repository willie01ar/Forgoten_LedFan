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

**Milestone 1 — the app is real without the hardware.**
Type a message, watch the polar preview update live, drive the simulated transport, full
unit test coverage of the domain. No USB required. This is achievable today.

**Milestone 2 — the app talks to the fan.**
Connect to `0x0C45:0x7701`, send frames, see the message in the air. Blocked only on the
wire protocol (see `protocol-discovery.md`).

**Milestone 3 — polish.**
Brightness, scroll speed, message persistence, multiple saved messages.

## Explicitly out of scope for now

- Image or animation upload. Text first.
- Supporting other fan models. One device, well.
- Any DriverKit extension. The device binds to Apple's generic HID driver; if a design
  seems to need a dext, that design is wrong.
