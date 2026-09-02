# Slice 6 — the last cable swap

**Date:** 2026-09-02
**Brief:** `docs/briefs/2026-09-02-slice-6-brief.md`. D15.
**Status:** complete. The batch was sent, the swap was made, the disc stayed dark. The
hardware path is closed in `protocol-discovery.md`, `hardware.md` and the findings log.

## What is being sent

One 256-byte image with four non-overlapping candidate tables in the vendor serializer's
stream format, at bases `0x00`, `0x18`, `0x40` and `0x80`, each with a signature made only
of all-on and all-off columns so that any row rotation or colour convention still shows
it. Full design, reasoning and the packet order are in `docs/protocol-findings.md`,
Slice 6. The files:

- `Tools/probe-output/2026-09-02-slice6-image.hex` — the block-0 image
- `Tools/probe-output/2026-09-02-slice6-packets.hex` — all 233 reports, in send order
- `Tools/HIDFan/slice6_batch.py` — builds both; `--send` sends

| If the disc shows | It came from |
|---|---|
| one narrow, sharp-edged bright wedge | P0, base `0x00`, bare stream |
| a comb of six thin lines | P1, base `0x18`, bare stream with its count/length bytes in the stall range |
| two thick bars with a gap | P2, base `0x40`, upload-header bytes ahead of the stream |
| one wide solid bright arc | P3, base `0x80`, bare stream |

## The owner's checklist

Do these in order. You do this once.

1. **Before the send.** Put the **data cable** into the head's port. Tell me "data cable in".
   I will confirm the fan is on the bus and send the batch; it takes about five seconds.
   Do nothing to the fan while I send. I will say **"swap now"** when it is done.
2. **The swap.** Unplug the data cable from the head. Connect the **power cable**. Press the
   power button so the head spins up.
3. **Look.** Dim the room if you can. Watch from the front, at eye level with the disc, for
   a full **60 seconds** from the moment it reaches speed. Then look once from a low angle.
4. **The button, while it spins.** Costs nothing (route 1f): a long press of two seconds,
   then a double press, then, if nothing changed, hold the button while reconnecting power.
   Note whether anything at all happens after each.
5. **Report exactly what you saw**, in these terms, even if the answer is "nothing at all":
   - any light: yes or no
   - if yes: its **shape** in your own words, then the closest match from the table above,
     or "none of them"
   - **how much of the circle** it covers, roughly, in clock positions or degrees
   - **where** on the disc: the whole arm length, the tip only, the hub only
   - **colour**, and whether it is steady, flickering, or only appeared during spin-up or
     spin-down
   - whether it **changed** over the 60 seconds or after any button press
6. Leave the fan on the power cable afterwards. Do not put the data cable back unless I ask.

**What counts as a result.** Any light at all: a smear, a single line, a flicker at spin-up.
Report it as seen, not as "it didn't work". Nothing at all is also a result, and the
important one to state plainly.

## Results

- **Send 1**, head on data-cable power: 233 reports, none failed, one `A2` write at 11 ms,
  no `A0` stall. Owner's observation, verbatim: "Still dark, motor spins fine." Button
  presses (long, double, hold-while-powering) did nothing.
- **Send 2**, owner-initiated and outside the brief's one swap: head on its own power cable
  (button off) and the data cable at the same time. It enumerated normally; the identical
  batch went in with no failures and no slow writes. Observation: "two or three leds
  flashing very dim when the head start spinning … third led from the hub and the third
  led from the tip … blue … instantly when the power arrives even before the blades starts
  spinning." Classified as a power-on indicator: pre-rotation, two fixed LEDs, while every
  lit column in the batch drove all eleven. Not a display of the data.
- **Outcome: dark.** None of the four candidates, in either addressing model or in blocks
  A2/A4, under either power configuration, is displayed.

Twelve swaps in total were made across the project, one more than the brief allowed,
because the owner proposed and paid for the extra one himself.

## Closing

`protocol-discovery.md` now opens with the closure, `hardware.md` records it and the
head's blue LEDs and power-on blink, and `protocol-findings.md` ends with the summary
written for someone arriving in two years with the same fan: what the head is, everything
that was tried, what is certain about the family, and the three things that would reopen
the question.

## Where the brief was wrong

1. **"E2a/E2b wrote the community's reconstruction, before we had the real one."** The
   vendor serializer emits the same bytes apart from the trailing-zero count. What *was*
   wrong was my E2a tool's write order, which shifted bytes 0–5 under 8-bit addressing;
   that made "bare stream at base 0, 8-bit" untested until this batch. Found by re-reading
   the tool, recorded in the findings, and covered by candidate P0.
2. **"Update `protocol-discovery.md` to mark 1c retired."** It already was, in the
   architect's own commit before this slice started. Nothing to do.
3. **Hedges "at 0x400 and up" are not free** under the 8-bit model: a 16-bit packet
   `A0 04 lo …` lands on an 8-bit device at address `0x04`. The batch orders the passes so
   the 8-bit device ends exactly right and accepts one five-byte splat on the 16-bit page
   0, where the only affected candidate had already been validly tested.
4. **The stall range as a placement clue** was carried into candidate P1 as designed, and
   it did nothing. The range remains unexplained; it is the one behaviour of this head that
   was never turned into a result.
5. **One swap.** The owner chose to spend a second one on a configuration nobody had
   considered, both cables connected. It was the right call to record and cheap to honour;
   it produced the only new facts of the day (blue LEDs, the power-on blink) and no display.
