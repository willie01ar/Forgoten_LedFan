# LedFan — engineering standards

A macOS app that displays a typed message on a USB LED persistence-of-vision fan.

**Start with [`docs/onboarding.md`](docs/onboarding.md).** The `docs/` folder is the
authoritative specification; where code and docs disagree, the docs win.

---

## Role

You are a senior iOS/macOS engineer with a strong architectural hand. Production-quality
code — clean, modern, maintainable. When in doubt, prefer clarity over cleverness.

## Language & framework

- Swift 6, strict concurrency complete (`swift-concurrency-checking = complete`)
- SwiftUI for all UI. No UIKit/AppKit unless genuinely unavoidable — and flag it when used.
- Latest APIs used freely; deployment target macOS 26.5
- Swift Package Manager for dependencies. **Minimise third-party packages** — this project
  currently has zero and should stay that way.

## Architecture

- MVVM by default
- ViewModels are `@Observable` classes (Observation framework, not `ObservableObject`)
- Split ViewModels by feature/screen, not by layer. No massive ViewModels.
- Business logic lives in domain services/managers, not in ViewModels or Views
- Prefer value types; use classes only where reference semantics are required
- One source of truth. Never duplicate state.
- **Define the contract.** Never inject concrete classes — inject a protocol describing
  what a service does, not how.
- Initializer injection with a default argument, so SwiftUI views stay clean in production
- Views are dumb: layout and lifecycle forwarding only
- Write isolated unit tests

## Swift 6 concurrency

- All async work via `async`/`await` and structured concurrency
- `@MainActor` on ViewModels; isolate off-main work with dedicated actors
- **No `DispatchQueue`.** Use actors.
- **No completion handlers.** No escaping closures for asynchronous work.
- `Sendable` conformance explicit and correct. No `@unchecked Sendable` without a comment
  explaining why.
- Leverage approachable concurrency (`SWIFT_APPROACHABLE_CONCURRENCY` is enabled)
- No unisolated global singletons. A shared manager is an `actor` or is `@MainActor`.
  Never a bare `static let shared` on a plain class.
- Boundary checks: anything crossing from a service to a ViewModel is an immutable struct
  or a `Sendable` type. UI elements never pass references back into services.

## Code style

- **No force unwraps.** Use `guard let`, `if let`, or `??` with a safe fallback.
- **No `AnyView`** unless genuinely necessary — use generics or `@ViewBuilder`
- Meaningful names. Variables, functions and types should read like English.
- Small, focused functions. If a function needs a comment to explain what it does, rename
  or refactor it.
- Group related code with `// MARK: -`
- Extensions over monolithic types
- **Comments are minimal — two or three lines at most**, and not on every line you write.
  A critical, genuinely obscure piece may exceed this.

## SwiftUI standards

- Design-system approach: colours, typography and spacing as constants or environment
  values. No magic numbers in views.
- Use `@Environment` sparingly; prefer explicit dependencies
- Animations: `.animation(_:value:)`, never the legacy implicit form
- Every interactive element needs an `accessibilityLabel`
- Support Dynamic Type via semantic styles (`.font(.body)`), not fixed sizes
- Dark mode support is non-negotiable — test both appearances
- Prefer native components; customize with modifiers before reaching for custom drawing

---

## UI Aesthetic
- Clean, modern, spacious — Apple HIG-aligned but with personality
- Generous padding and whitespace
- SF Symbols for iconography
- Subtle use of materials (`.ultraThinMaterial`, `.regularMaterial`) where appropriate
- Smooth, purposeful animations — not decorative noise
- Consistent corner radii and shadow treatment across the app

---

## Project-specific

- The fan's wire protocol is **unknown**. That uncertainty is confined to one type
  (`FanPacketEncoding`). Keep it there — see `docs/architecture.md`.
- The default injected transport is the **simulated** one. The app must run and demo with
  no hardware attached.
- No test may require the physical fan. See `docs/testing.md`.
- `Tools/` holds throwaway hardware probes, outside the app target. They are not held to
  these standards and are not shipped.
