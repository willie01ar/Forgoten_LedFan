# Slice 6 — the last cable swap

**Date:** 2026-09-02
**Brief:** `docs/briefs/2026-09-02-slice-6-brief.md`. D15.
**Status:** batch designed and written to `Tools/probe-output/` before sending; awaiting the
owner's data cable, then the send, then the one swap. Results section follows the observation.

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

*(to be filled in after the swap)*

## Where the brief was wrong

*(to be completed with the results)*
