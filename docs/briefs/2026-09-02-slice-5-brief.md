# Slice 5 brief — static analysis of the vendor software

**Date issued:** 2026-09-02
**Prerequisite reading:** `docs/protocol-findings.md`, the section dated 2026-09-02
("THE VENDOR SOFTWARE WAS FOUND"), then `docs/decisions.md` D5, D8, D9.

---

## Where we are

Route 1d found the vendor editor. It is in `Vendor/` in this repository: `LedFan.exe`
(MFC, 2014), `WxkUSB.dll` (a renamed `SonixUSB.DLL`), `LedFan.Ini`, five font tables, two
large Chinese fonts, the vendor manual, and one saved project file with real message data.

Slice 3 concluded no software existed for this family. That conclusion is now void.

**This slice is pure static analysis. No hardware, no cable swaps, no writes to the fan.**
Everything here can be done at a desk with the fan unplugged.

## Non-negotiable

**Do not execute `LedFan.exe`, `WxkUSB.dll`, or anything else in `Vendor/`.** Not under
Wine, not in a VM, not "just to see". It is a fifteen-year-old Windows binary from a
hobbyist mirror. Static analysis only: `pefile`, `capstone`, a disassembler, a hex editor.

`Vendor/` is third-party material. Do not modify it, do not reformat it, and do not move it
into the app target.

---

## Task 1 — How does `LedFan.exe` build the packet?

This is the whole slice. Everything else is secondary.

`WriteUSB` (RVA 0x1180 in `WxkUSB.dll`) is a thin `WriteFile` wrapper and does no framing,
so the buffer is constructed in the exe. Find the construction.

Starting points already established: `OpenUSBDevice` is called at file offsets 0x1fdde,
0x2019f and 0x20314, each as `push 0x7160 / push 0x0C45 / call`. The write path is near
those call sites. Work forward from them to the `WriteUSB` calls and back from there to the
buffer.

**Acceptance**
- [x] The report size and layout are documented: what the first byte is, whether there is
      an index or address, how many payload bytes, and how a message is split across
      reports.
- [x] The full upload sequence is described: what is sent before the data, what after, and
      in what order the eight message slots are written.
- [x] Any handshake, header or terminator packet is identified.
- [x] Written up in `docs/protocol-findings.md` with the offsets you worked from, so the
      analysis can be checked and resumed.

If the analysis stalls, say so and document how far it got. A partial map with honest gaps
is worth more than a confident guess — this project has already been burned once by a tidy
hypothesis with an invented premise.

---

## Task 2 — Decode the font tables

`THE_7ASCII.bin` is 80 + 256x8 bytes; `the_11ASCII.bin` and `the_16ASCII.bin` are
80 + 256x16. That reads as an 80-byte header plus 256 glyphs of 8 columns, 1 byte per
column at 7 LEDs and 2 bytes at 11 and 16.

The data is obfuscated: high bytes are uniformly 0x2f or 0x3f and nothing renders directly.
It is **not** the 0xA4 subtract scheme from the sibling reverse-engineerings.

You have known plaintext: glyph index 0x41 must look like an "A", 0x20 must be blank.
That is a strong constraint — use it.

**Acceptance**
- [x] The encoding is identified, or the attempt is documented with what was ruled out.
- [x] With it applied, `the_11ASCII.bin` renders recognisable ASCII glyphs at the right
      indices. Include an ASCII-art dump of a few letters as evidence.
- [x] The 80-byte header's fields are described as far as they can be.
- [x] If the encoding resists, say which schemes were eliminated (XOR constant, additive
      constant, position-dependent, bit reversal, nibble swap) rather than leaving it open.

---

## Task 3 — Parse `Rien compris.LDAT`

A saved project, 7532 bytes, with real message content. The editor's save format is likely
close to what it uploads, and it is far easier to read than machine code.

**Acceptance**
- [x] The file's structure is described: header, message count, per-message fields.
- [x] The eight slots are located, along with per-message effect bytes matching the
      `LedFan.Ini` vocabulary (nine opening effects B1-B9, four middle D1-D4, seven closing
      E1-E7).
- [x] Any relationship to the on-wire format is noted.

---

## Task 4 — Report what this means for our fan

The editor hardcodes `0x0C45:0x7160`. Ours is `0x0C45:0x7701`, and holds 26 characters
where this build's limit is 20. Same vendor and same DLL family, different product.

**Acceptance**
- [x] A clear statement of which findings should transfer to `0x7701` and which are
      specific to `0x7160`, with reasoning.
- [x] A recommendation on whether the `A0 <byte>` behaviour observed on our head
      (`protocol-findings.md`, slice 3) is consistent or inconsistent with the framing you
      found.
- [x] A proposed next experiment for the owner, costing at most one cable swap, if the
      analysis supports one. If it does not, say so.

---

## Task 5 — Raise the D5 question

The editor ships its own font tables, which is strong evidence the **host rasterises and
uploads columns** rather than sending characters to a firmware font. D5 assumed the
opposite was likely and deliberately hedged the transport contract so either could be true.

**Acceptance**
- [x] A recommendation to the architect on whether D5 should be revised, with the evidence
      from tasks 1-3 behind it. Do not change the contract yourself — D5 is an architect
      decision and this is a report, not a refactor.

---

## Out of scope

- Any code change in the app target. This slice produces knowledge, not features.
- Any contact with the fan.
- Running any vendor binary.
- Milestone 3 work (scrolling, persistence). It waits.

## Definition of done

1. `docs/protocol-findings.md` extended with the analysis, including offsets and the
   negative results.
2. An acceptance report at `docs/reports/2026-09-02-slice-5-*.md`, with the usual section
   on where this brief was wrong.
3. Everything committed. `Vendor/` committed unmodified.
4. No change to `LedFan/` source.
