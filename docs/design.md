# Design

## Window

Single window, one view. Vertical stack: preview, then controls, then error area.
Minimum width 360pt. The preview is the hero — it is the reason the app exists.

## The preview

A circular polar plot on a dark ground. Each column maps to an angle around the circle;
each lit bit maps to a dot at a radius between hub and tip. This is not decoration: it is
the honest depiction of what a persistence-of-vision fan paints, and it makes rasterisation
bugs visible instantly.

Do not animate rotation. The static polar image *is* what the eye sees when the fan spins;
adding rotation would show less, not more.

## Design tokens

No magic numbers in views. Spacing, sizes and colours come from `DesignSystem/`:

```swift
enum Layout  { tight, standard, loose, simulatorSide, ledDiameter }
enum Palette { litLED, unlitLED, simulatorBackground }
```

Extend these rather than introducing literals. A literal in a view body is a defect.

## Typography and Dynamic Type

Semantic styles only — `.body`, `.caption`, `.callout`. No fixed point sizes. The layout
must survive the largest accessibility text sizes without clipping controls.

## Dark mode

Non-negotiable, and test both appearances. The preview's dark ground is intentional in both
appearances — it represents unlit air, not the window background. Use
`Palette.simulatorBackground`, never a raw `Color.black`.

## Colour

The lit LED colour derives from the accent colour so the app respects the system tint.
Never encode meaning in colour alone — connection state is also carried by text.

## Animation

`.animation(_:value:)` bound to the frame. Never the legacy implicit form.

## Accessibility

- Every interactive element carries an `accessibilityLabel`. Placeholder text is not a
  label.
- The preview is a single accessibility element labelled with the message it is showing,
  not a mass of individual dots.
- Errors are announced as errors, not as decoration.

## Tone

The one piece of copy that matters is the missing-device message. The user's most likely
mistake is having only the power cable connected, so say that plainly rather than "device
not found".
