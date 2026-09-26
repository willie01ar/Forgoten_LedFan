# Design

## Window

Single window, one view, stacked: the preview on top, square and centred, the eight
fields and controls below it. Minimum width 600pt, ideal 900pt. A two-column arrangement
was built in slice 11 and reverted the same day at the owner's request after seeing it;
the preview is the hero — it is the reason the app exists — and it reads best on top.

**Fields.** Eight text fields, one per message, visible at once, each with its own
`n/26` counter and an accessibility label "Message 1" … "Message 8". Tab moves through
them in order. The preview follows keyboard focus; with no focus it shows the first
filled field; with nothing filled it is blank and says so.

**Transport.** USB fan first in the picker and selected at launch (D23). Not connected is
a resting state in secondary colour; error copy appears only after Connect fails.

## The preview

A circular polar plot on a dark ground. The frame is one revolution at fixed angular
resolution (D1): each of its columns maps to an angle, so a short message occupies a
proportional arc centred on the top of the disc and the rest stays dark. Each lit bit
maps to a dot at a radius between hub and tip, glyph tops at the rim so text on the
upper arc reads upright. A faint ring marks the LED band.

**Send.** The button reads "Send" and a caption says it publishes the filled messages and
replaces everything the fan holds; empty fields are not sent (D22). Success is one plain
line, "Sent 3 messages to …"; report counts, bytes, timings and echo statistics never
appear in the interface (D24). Every transport error message does, verbatim.

**Motion.** A message longer than one revolution scrolls towards the left of the top arc
at `Motion.scrollColumnsPerSecond`, so new characters enter on the right, and wraps
through `Motion.scrollGapColumns` of dark. Shorter messages stand still. The preview is a
`TimelineView` reading a pure frame-for-a-date function; it pauses under Reduce Motion,
when the scene is inactive, and when there is nothing to scroll. The accessibility label
gains ", scrolling" while it moves. This is not decoration: it is
the honest depiction of what a persistence-of-vision fan paints, and it makes rasterisation
bugs visible instantly.

Do not animate rotation. The static polar image *is* what the eye sees when the fan spins;
adding rotation would show less, not more.

## Design tokens

No magic numbers in views. Spacing, sizes and colours come from `DesignSystem/`:

```swift
enum Layout  { tight, standard, loose, simulatorSide, simulatorHubRatio, simulatorTipRatio,
               ledDiameter, cornerRadius, minimumWindowWidth, shadowRadius }
enum Palette { litLED, unlitLED, simulatorBackground, simulatorShadow,
               statusIdle, statusConnected, statusFailed, error,
               counterWithinLimit, counterOverLimit }
enum Motion  { scrollColumnsPerSecond, scrollGapColumns, frameInterval }
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
