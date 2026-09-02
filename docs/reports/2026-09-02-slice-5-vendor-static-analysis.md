# Slice 5 — static analysis of the vendor editor

**Date:** 2026-09-02
**Brief:** `docs/briefs/2026-09-02-slice-5-brief.md`, five tasks.
**Status:** complete. Static analysis only: nothing in `Vendor/` was executed or modified,
no code in the app target changed, nothing was sent to the fan.

## Summary

Task 1 is answered end to end: the executable resolves the USB library at runtime, builds
9-byte reports (report id, seven payload bytes, byte-sum checksum), sends a `40 40` header
and `40 23` data reports five stream bytes at a time, waits for a 3-byte acknowledgement
after each with status `0x80`, and the stream it sends is the message table the sibling
reconstructions described, now read from the serializer itself with every offset noted.
Task 2 found the font decoder in the executable: the tables are not obfuscated; the odd
bytes are padding the readers never touch, and the even bytes are inverted for the 11- and
16-row tables and raw for the 7-row one. Task 3 decoded the project file completely. Tasks 4
and 5 are answered in `docs/protocol-findings.md`: the table model transfers to our head,
the framing does not, and D5's premise should be revised.

| Definition of done | Result |
|---|---|
| `protocol-findings.md` extended with offsets and negatives | Yes, section "Slice 5". |
| Acceptance report with "where the brief was wrong" | This document. |
| Everything committed, `Vendor/` unmodified | Yes. |
| No change to `LedFan/` source | None. |

## Task by task

- **Task 1.** Send routine at file `0x020170`, upload routine at `0x020290`, serializer at
  `0x01f7f0`, mode setter at `0x01f290`, dynamic import at `0x019866`. Report layout, upload
  sequence, header, checksum, acknowledgement and slot order are documented. One gap: the
  mode-1 bit permutation at `0x01fb3b`–`0x01fbc5` is located and characterised but its exact
  mapping was not derived.
- **Task 2.** Decoders at `0x01ae20` (7-row), `0x01aea0` (16-row), `0x01b8fa` (12-column
  FH). Rule, strides, origin, row orders and ASCII-art evidence for A, B, I, L, 0, 8 from all
  three ASCII tables. Eliminated schemes listed.
- **Task 3.** 140-byte header with eight per-slot character counts at `0x4c`, then 88
  records of 84 bytes, each a character with its rasterised 16-bit columns. Four French
  messages. Effects are not stored in the file.
- **Task 4.** Transfer analysis and the `A0` question, both in the findings. No experiment
  with good odds; one low-probability single-swap variant noted and deferred to route 1b.
- **Task 5.** Recommendation to revise D5's premise and keep its contract, plus two numbers
  for D1 (142 columns).

## Where the brief was wrong

1. **The folder is `vendor/`**, lower case, on disk and in git. The brief and the findings say
   `Vendor/`. Left as is; renaming third-party material was not in scope.
2. **"80 + 256 × n" font layout.** There is a 4-byte magic, glyph 0 is the space, the 7-row
   stride is 10 bytes and the 11/16-row stride is 32, and only the even bytes carry data. The
   "1 byte per column at 7 LEDs" reading was right in spirit and wrong in the file: every
   column occupies a 2-byte slot in all three tables.
3. **"The data is obfuscated."** It is not, in any cipher sense: inversion for two tables,
   nothing for the third, and discarded padding bytes. The known-plaintext constraint was
   the right idea; the reason it kept failing was the layout, not the transform.
4. **Per-message effect bytes in the `.LDAT`.** They are not saved; the serializer reads them
   from the dialog at upload time.
5. **"This build's limit is 20."** The sample project holds messages of 22 and 25 characters;
   the 20 is a per-font UI limit for one LED type, not a format limit. The real constraint is
   column width (`LedScrW11=142`) and the 2 KB store.
6. **Starting offsets.** `0x1fdde`, `0x2019f` and `0x20314` are the `push 0x7160`
   instructions; the calls are a few bytes on. Harmless, noted for whoever resumes.
7. **"`WriteUSB` … does no framing."** Confirmed, and the exe's framing turned out to be
   exactly the sibling reconstructions' shape, which the brief treated as possibly wrong.
   The reconstructions were right about `0x7160`; they were never about `0x7701`.

## Open questions for the architect

1. Revise D5 as recommended? (Keep the contract; drop the firmware-font branch; the future
   serializer rasterises through the app's rasterizer.)
2. Adopt 142 as the 11-LED preview width in D1?
3. Is the low-probability "header-bytes-in-EEPROM" swap worth one of the owner's swaps now,
   or does it wait for route 1b as recommended?

## Proposed next slice

Route 1b preparation only, if the owner is willing to photograph the head's PCB: the
analysis has extracted everything the editor can say about the table, and the remaining
uncertainty is on the head, where only a read path resolves it. Otherwise, Milestone 3.
