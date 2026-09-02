# Slice 3 — the probing session

**Date:** 2026-09-01, afternoon and evening, with Willie at the fan.
**Scope:** `protocol-discovery.md` routes 1 and 3 against the real head, with the owner
observing the blades. Slice 2 code (transport picker, hardware checklist test) is still
uncommitted and awaiting approval; this slice adds only tools and documentation.
**Status:** protocol not found. The factory demo on the head has been erased by probing.
Stopping here by agreement rather than spending more cable swaps.

## Summary

The session established how this fan works physically and electrically, closed off every
published lead, and ended with the display dark. The single most consequential fact is
physical: the data port is on the rotating head, so the fan cannot spin while connected,
and every observation costs the owner a cable swap. The second is that the head is
write-only over USB. The third is that a blanket sweep of all two-byte headers with an
all-ones payload erased the factory demo, which is both the strongest evidence that the
`A0` header family writes into the head's storage and the reason the fan now shows nothing.

## What was learned (all recorded in `docs/protocol-findings.md`)

1. **Two mutually exclusive phases.** Program with the data cable in and the head still;
   display with the power cable in. `display(_:)` on hardware means "store", not "show".
2. **Write-only.** No interrupt-IN report ever, through two independent listeners. Every
   GET_REPORT returns the last USB SETUP packet, so the control pipe cannot carry a reply.
3. **`IOHIDManagerOpen` breaks report transfers** on this device; the transport now
   matches and opens the device directly.
4. **`A0` is the only header the firmware processes.** Only `A0 xx` packets ever show
   EEPROM-like write timing (27–61 ms) or the reproducible 5 s host timeout, always with
   the second byte between 0x18 and 0x23, in four separate runs, regardless of payload.
   `0xA0` is the I2C write address of a 24Cxx EEPROM; `A0 <addr> <data>` as a raw I2C
   write is the best model of the bridge.
5. **The demo is gone** after the all-ones header sweep, and stayed gone through: zeros in
   four 256-byte blocks, the sibling fans' stored stream in both encodings and both
   addressing models, and a full header sweep with a `55 AA` payload. The display is
   driven by a parsed table whose format is not the published one.
6. **Route 1 is closed for now.** The only archived vendor editor targets product
   `0x7160`; `0x7701` appears nowhere in it, nowhere online, and not in the USB ID
   registry. The two GitHub reimplementations describe the `0x7160` and `1a86:5537`
   siblings, whose framing and table were tested and rejected here.

## What was built

- `Tools/HIDFan/hidfan.swift`: IOReturn decoding, `listen`/`feature` modes, control-pipe
  input read, refuses to send on unparseable input.
- `Tools/HIDFan/*.py` with a README: hidapi-based sweeps, timed sweeps, block fills, and
  stream writers hedged for both EEPROM address models. Third-party dependency, tools only.
- `Tools/probe-output/`: the exact packet streams sent.
- `docs/hardware.md`: the two-phase topology, the manager-open rule, the echo behaviour.
- `docs/protocol-findings.md`: the full log plus an end-of-day summary and next steps.
- `docs/onboarding.md` and `docs/current-state.md` updated to match.

## What was decided

- **Feature-report writes were not sent.** I asked; consent was not given; they stay off.
- **Stop spending swaps.** Nine swaps were made today. Each remaining blind experiment has
  low odds and the owner's time is the scarce resource.

## What the specification got wrong

- `protocol-discovery.md` treats the interrupt-IN endpoint and the feature report as
  feedback channels. On this head neither carries anything.
- The docs assumed live observation. There is none; the oracle is a cable swap.
- `hardware.md`'s guardrail about bricking was about the right thing for the wrong reason:
  the risk that materialised was not a bricked MCU but an erased EEPROM.

## Open questions for the architect

1. Do we accept the fan as "programmable only once the table format is known" and pause
   Milestone 2, shipping Milestone 1 plus the transport picker as the deliverable?
2. Is feature-report probing worth the owner's consent, given it is the one untouched
   channel and the demo is already lost?
3. Angular resolution (slice 1, question 1) is still open and now matters less until the
   table format exists.

## Proposed next slice

Only if the software for a `0c45:7701` fan turns up, or the architect approves
feature-report probing. Otherwise: commit slice 2, tick what is demonstrable, and leave
`FanPacketEncoding` as the documented seam with `A0 <addr> <data>` as the transport-level
shape the real encoder will emit.
