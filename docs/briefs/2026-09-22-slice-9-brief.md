# Slice 9 brief — the real protocol

**Date issued:** 2026-09-22
**Prerequisite reading:** `docs/protocol-findings.md`, section 2026-09-22 ("THE PROTOCOL EXISTS
IN PUBLIC"), then `docs/decisions.md` **D17**, D16 and D8.

## Where we are

Our fan (`0c45:7701`, PEARL PX5939) has two open-source drivers: **Ventto/pearlfan** (C, GPLv3)
and **pearlfan-rs** (Rust, MIT/Apache-2.0, `VID 0x0C45`, `PID 0x7701`). The header opcode is
`A0`, which is the only header our head ever reacted to. This slice turns that into a working
fan.

## Hard rule: licensing

**Do not copy any code from Ventto/pearlfan (GPLv3).** You may read pearlfan-rs
(MIT/Apache-2.0) to learn the exact packet layout. Reimplement from the facts in Swift, and
credit both projects in the README.

## Task 1 — Pin the protocol down exactly

From pearlfan-rs, document in `protocol-findings.md`:
- the header packet, byte by byte on the wire (the 64-bit constant, byte order, the effect
  field's layout and valid effect codes, where the image id goes)
- data packets: 39 per image, 4 columns each, the word endianness, which bit is the innermost
  LED and which the tip, whether 1 means lit, and the column order (does column 0 come first?)
- how many images get sent: always 8, or only non-empty ones, and what an unused slot contains
- the interrupt-IN read after each packet: length, timeout, and what is done with its content
- any delays, init or finish sequence

**Acceptance**
- [x] The layout is written down with a worked example: the full packet list for a
      one-message table containing "A".
- [x] The source file and line for each fact is cited, so the work can be checked.

## Task 2 — A reference-exact encoder

A pure `nonisolated` Swift type producing the packet list for `[FanMessage]`, rasterising
through the injected `MessageRasterizing` at 11 LEDs x 156 columns.

The app's current preview uses a 6-column glyph pitch, and 26 x 6 = 156, so it matches this
geometry. If it turns out not to, report it rather than bending the rasterizer.

**Acceptance**
- [x] **Golden test:** for at least three inputs (empty slot, "A", a full 26 characters), the
      Swift output equals pearlfan-rs's output byte for byte. Generate the reference bytes by
      building and running pearlfan-rs *in a dry-run mode or a test harness*. If it has no
      dry-run, capture its packets at the libusb layer, or hand-derive them from Task 1 and
      say that you did.
- [x] Effects map to the D-vocabulary where it matches; default is "remain".

## Task 3 — Wire it and test on the fan, once

Make it the hardware transport's default protocol (D17). Keep `GenerationTwoTableSerializer`
selectable.

The sequence matches the reference driver: data cable in, fan **switched off** (the
programming state), send, then swap to power. Implement the interrupt-IN read after each
packet with a short timeout. Log whether each read returned data, and what it returned.

**Owner checklist (write it out for Willie before sending)**: which cables, switch position,
the command or button, then the swap and what to look for. One message, something
unmistakable like `HELLO WILLIE`.

**Acceptance**
- [x] One send, one swap, observation recorded verbatim.
- [x] Interrupt-IN results recorded: did the head acknowledge? Include the bytes. (Yes, all 40 by timing; bytes pending the log copy.)
- [ ] If it works: screenshot or photo in `docs/reports/images/`, `features.md` F5 closed, D9's
      history annotated with how it ended.
- [ ] If it doesn't: stop after that one swap. (Not applicable: it worked.) Report which bytes went out, the ack results,
      and the difference from the reference. Don't iterate blind.

## Out of scope
- Copying GPLv3 code.
- Feature reports (D7).
- More than one cable swap without the architect.

## Definition of done
1. Builds with no warnings; all tests pass, including the golden tests.
2. Findings, report at `docs/reports/2026-09-22-slice-9-*.md` (with "where the brief was wrong"),
   README credits.
3. Everything committed.

---

# Addendum — 2026-09-25

Four changes since this brief was written. The tasks stand; these amend them.

## 1. The hardware is a NEW fan, and there are two of them

The original head was destroyed. Fan A is a PowerTRC unit, confirmed **`idVendor 0x0C45`,
`idProduct 0x7701`** — the same PID, so nothing in this brief changes.

**Fan B exists, is sealed, and must never receive a byte.** It is the known-good control this
project never had. Do not connect its data cable. Do not ask for it. If A becomes unusable,
that is an architect decision, not a build-session one.

## 2. Check the box for the vendor CD — do this before Task 1

The PowerTRC fan ships with a **3-inch mini-CD and a separate programmable USB cable**. That
disc is very likely the editor for **this exact PID**, which is the artefact the project hunted
for three weeks and never found. Everything in `vendor/` today is the *generation-2* editor for
`0x7160`.

If the owner can read the disc (a mini-CD needs a tray-loading drive; the MacBook has no
optical drive at all), copy its entire contents into `vendor/px5939/` and analyse it the way
slice 5 analysed the other one. **Never execute it.** It would give an independent confirmation
of the packet layout, the real effect codes, and the firmware font tables — including the
lowercase glyphs D18 is about.

Do not block on this. If the disc can't be read, proceed with pearlfan-rs as the reference.

## 3. Known plaintext now exists

Fan A's factory demo has been transcribed in `protocol-findings.md` (2026-09-25):
`Hello World. I hold 8 Msg.` / `26 letters in each Msg` / `I'm your *NOTE PAD*` /
`*Mom Pick me up @4P*`. The first is exactly 26 characters.

Use it. If a capture or a dump ever appears, those are the bytes to look for. And note what it
implies for Task 3: the demo occupies all 8 slots, so **establish what happens to the slots you
don't write** — are they preserved, blanked, or filled with junk? Record the answer; it is a
protocol fact nobody has.

For the first send, keep `HELLO WILLIE` in slot 1 as specified, and leave the rest alone.

## 4. D18 (lowercase glyphs) is adjacent, not blocking

The device's own demo is mixed case, so its font has lowercase and ours does not. D18 covers
extending `GlyphFont`. It can land before, alongside or after this slice — but if the first
send goes out with the uppercase-only table, say so in the report, so nobody mistakes
`HELLO WILLIE` rendering in caps for a protocol bug.
