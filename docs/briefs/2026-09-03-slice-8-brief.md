# Slice 8 brief — give the writer a real body

**Date issued:** 2026-09-03
**Prerequisite reading:** `docs/decisions.md` **D16** (new — it supersedes D9), then D8 and
D5. The byte-level source of truth is the Slice 5 section of `docs/protocol-findings.md`,
Task 1 (the serializer at file `0x01f7f0`, the upload routine at `0x020290`, the send
routine at `0x020170`).

Independent of slice 7. Run either order.

---

## Why this slice exists

`MessageTableSerializing` has one conformance and it throws. D8 split the encoder into a
known framing layer and an unknown table layer specifically so that a discovered format
would change one type and nothing else — but that claim has never been tested, because no
format was ever implemented.

Slice 5 recovered the generation-2 table format in full from the vendor's own serializer.
Implementing it makes both layers real, exercises the seam, and leaves the writer's shape in
place for a Version 3 format that may never come.

**It is expected not to light the disc.** `0x7701` ignored this format in every position and
encoding tried. Build it correct, not hopeful.

---

## Task 1 — `GenerationTwoTableSerializer`

A pure function from `[FanMessage]` to `[UInt8]`, implementing the stream documented in the
Slice 5 findings:

- global header, then per-message `[columns+2][00][style][open<<4|close][00]`
- characters emitted **last to first**, columns as 2-byte little-endian words, bits 0-10
  pixels, bit 13 the colour flag
- trailing `00` bytes after the final message
- the 2 KB ceiling the vendor calls "IC ROM Over"

Rasterise through the app's own `MessageRasterizing`, injected — per D13, the host
rasterises, and this serializer must not carry a second font.

**Acceptance**
- [x] Byte-for-byte tests against the layout in `protocol-findings.md`: message count, the
      `columns+2` field, effect byte packing, reversed character order, little-endian
      columns, trailing zeros.
- [x] A message exceeding the 2 KB store is rejected with a clear error, not truncated.
- [x] Pure and `nonisolated`. No I/O, no device knowledge, no framing.
- [x] The type's name and doc comment say plainly which generation of hardware it targets.

---

## Task 2 — Wire the transport

`EEPROMWriting` already frames `A0 <addr> <data…>` and is tested. Connect serializer →
writer → `IOHIDDeviceSetReport`.

**Acceptance**
- [x] `HIDFanTransport.store(_:)` sends. `.writingDisabled` is gone.
- [x] **No hang on silence.** Our head never acknowledges; the vendor protocol expects a
      3-byte ack with status `0x80`. Absence of an ack is normal — do not retry, do not
      block, do not report failure. Document this in two lines at the call site.
- [x] Writes stay on the actor. Nothing crosses to the ViewModel but `Sendable` values.
- [x] The exact packet stream of every send is written to a file, so a send is reproducible
      afterwards.

---

## Task 3 — Tell the truth in the UI

This is the part that matters most, and it is easy to get wrong by being either falsely
encouraging or uselessly vague.

**Acceptance**
- [x] Selecting the hardware transport states plainly that the message format belongs to a
      different generation of fan and is not expected to produce a display.
- [x] A completed send reports what actually happened — bytes sent, no acknowledgement
      received — and never the word "sent" alone, which reads as success.
- [x] The copy does not blame the user's cable or setup. This is our gap.
- [x] A unit test asserts the copy contains no unqualified success language.

---

## Task 4 — Prove the seam

The claim behind D8 and D16 is that a new format changes exactly one type.

**Acceptance**
- [x] A second, deliberately trivial `MessageTableSerializing` conformance exists in the test
      target only, and the whole stack works with it injected — proving the seam without
      shipping a second format.
- [x] State in the report whether anything above the transport had to change. If something
      did, the boundary is wrong and that is the finding.

---

## Out of scope

- Feature reports (D7 stands).
- Sweeps, walking bits, header probes — those stay in `Tools/`.
- Any cable swap, or asking the owner to observe anything. This slice ends at "the bytes
  went out". Nobody watches the fan.
- Chasing a display. If it lights, that is a finding for the architect, not a reason to
  start iterating.

## Definition of done

1. Builds with no warnings; all tests pass.
2. `features.md` updated — F5's "a message appears on the blades" box stays open, and should
   now say the writer exists and the format is the wrong generation.
3. Acceptance report at `docs/reports/2026-09-03-slice-8-*.md`, with the usual section on
   where this brief was wrong.
4. Everything committed.

## Note

The point is a correct writer, not a working fan. If it is built well, the day someone finds
a Version 3 format the work is one new conformance and an afternoon — and if nobody ever
does, the app still contains an honest, tested implementation of a real protocol rather than
a stub that throws.
