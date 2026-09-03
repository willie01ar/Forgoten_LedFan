# Slice 8 — give the writer a real body

**Date:** 2026-09-03
**Brief:** `docs/briefs/2026-09-03-slice-8-brief.md`. D16 supersedes D9.
**Status:** complete. Nothing was sent to the fan and nobody watched it; the slice ends at
a writer that is built, tested and wired, as the brief asked.

## Summary

Both halves of D8 are now real. `GenerationTwoTableSerializer` produces the `0c45:7160`
family's message table byte for byte from the stream mapped in slice 5, rasterising through
the injected rasterizer. `EEPROMWriter` frames the whole 2 KB store as `A0`…`AE` block
reports. `HIDFanTransport.store(_:)` sends, treats silence as normal, counts a 5-second hold
without failing, logs every send's packets to a file, and returns a receipt in words that
never claim success. The UI shows the generation caveat before a send and the receipt after
it. A trivial test-only serializer runs through the same writer unchanged, which is the
seam D8 promised and D16 asked to see proven.

| Definition of done | Result |
|---|---|
| Builds with no warnings; all tests pass | Yes. 104 unit tests, 8 UI tests, 2 hardware checklist tests skipped without the flag. 0 warnings. |
| `features.md` updated, F5 blades box open with the reason | Yes. |
| Acceptance report with "where the brief was wrong" | This document. |
| Everything committed | Yes. |

## Task by task

### Task 1 — `GenerationTwoTableSerializer`
- Pure, `nonisolated`, `Sendable`. Rasterizes through `MessageRasterizing`, injected, at the
  generation's 11 LEDs. No I/O, no device knowledge, no framing.
- Stream, from the findings rather than the brief: `00`, `0x80 | count`; per non-empty
  message `[columns+2] 00 [style] [open<<4 | close] 00 00`, the characters' columns last to
  first as little-endian words with pixels in bits 0–10 and the red flag in bit 13, then
  `00 00`; eight `00` after the last message. Style defaults to 3, "Remain"; effects to 0.
- Refuses a table over 2 048 bytes with `.tableTooLarge(bytes:limit:)`, and a message set
  with nothing to write with `.nothingToStore`, as the vendor does ("No Data Send!").
- Tests: a hand-written byte-for-byte expectation using a stub rasterizer with known
  columns; count byte with an empty message skipped; the `columns+2` field; effect packing;
  reversed character order against the real rasterizer; masking and the colour bit; the
  ceiling refused rather than truncated; a real 26-character message fits; purity.

### Task 2 — the transport
- `EEPROMWriting` now takes a 16-bit address and produces 24C16 block headers
  (`0xA0 | block << 1`), never crossing a 256-byte block boundary. Tested: headers per
  block, a chunk split at a boundary, a full 2 KB table in 344 reports.
- `FanTableWriter` joins serializer and framing with no I/O. `PacketLog` writes one hex file
  per send to `Application Support/LedFan/sends/`, one report per line, so any send can be
  replayed; tested line for line.
- `HIDFanTransport.store(_:)` calls `IOHIDDeviceSetReport` for each report, the only such
  call in the app target. It reads nothing: two lines at the call site say the vendor
  protocol expects a 3-byte ack and this head never sends one, so silence is normal. A
  `kIOReturnTimeout` is counted as a held write and the loop continues, because that is the
  5-second stall the probes saw and the head recovers from; any other error is thrown as
  `.writeFailed`. Everything stays on the actor; only `FanStoreReceipt`, a `Sendable`
  value, crosses to the ViewModel. `.writingDisabled` and the throwing placeholder are gone.

### Task 3 — telling the truth
- `FanStoreAvailability` gained `.experimental(caveat:)`. The hardware transport's caveat:
  "This fan is a different generation from the one whose message format the app implements.
  Send will write the bytes, but nothing is expected to appear on the blades." Send stays
  enabled; the ViewModel shows the caveat.
- The receipt after a send: "Wrote N reports (B bytes) to the fan. No acknowledgement came
  back, which is normal for this fan. Nothing is expected on the blades." plus a held-writes
  sentence when one occurred. The word "sent" does not appear.
- A unit test asserts both texts contain no unqualified success language and never mention
  the cable.

### Task 4 — the seam
`TrivialTableSerializer`, test target only, emits the slot byte and the UTF-8 text.
Injected into `FanTableWriter` it produces the expected `A0`-framed report with no other
change. **Nothing above the transport had to change for the format.** Two things above it
did change for other reasons, and the report should say so: `store(_:)` now returns a
`FanStoreReceipt` so the UI can state what happened (Task 3), and `FanStoreAvailability`
gained a case for the same reason. Both are about honesty, not format; a Version 3
conformance would touch neither.

## Where the brief was wrong

1. **The per-message header.** The brief writes it as `[columns+2][00][style][open<<4|close][00]`,
   one trailing zero. The serializer at `0x01f7f0` emits two for the 11-LED mode
   (`0x01fa2a`, "and a second 00 unless mode == 0"). The findings were followed, as the
   brief itself instructs.
2. **"`EEPROMWriting` already frames `A0 <addr> <data…>` and is tested. It stays."** Its
   8-bit address could reach only the first 256 bytes, and the generation-2 table for a
   single 26-character message is 328 bytes. It had to grow block addressing to be a
   correct writer for the store the vendor calls "IC ROM". D8's shape was right; its
   address width was not.
3. **"Nothing above the transport changes."** True for the format, as Task 4 shows, and
   not quite true for the slice: the receipt and the experimental availability case are
   contract changes, made so the UI can be honest. Stated rather than hidden.
4. **The column bit layout.** The brief specifies pixels in bits 0–10 and the colour in
   bit 13, which is the sibling's captured wire format. Slice 5 found the vendor's own font
   tables and project file use three other rotations, and its mode-1 permutation was never
   decoded. The captured layout is the one with evidence of reaching a fan, so it is what
   was built, and the type's comment says so.
5. **"Independent of slice 7."** It was, except for two UI assertions on the confirmation
   line, which now carries the receipt's words.

## What is left

Nothing in the app. The writer is exercised end to end against the only format anyone has
recovered; the day a Version 3 format arrives, it is one conformance and an afternoon, and
the tests for the seam already exist.
