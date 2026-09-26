# Retrospective — how LedFan actually got solved

Written 2026-09-25, after slice 9 put `HELLO WILLIE` on the blades. This is the honest
account, including the parts that were wasted effort and the mistakes that were mine.

---

## The one-line answer

We found two open-source drivers for the exact device — `0c45:7701` — after three weeks of
concluding no such thing existed.

## Why we found them in September and not in August

Not because we searched harder. **The search space was wrong the entire time.**

Every query for three weeks was a variation of `0c45:7701`, or "the vendor software for this
chip". That question structurally cannot find those drivers: neither `Ventto/pearlfan` nor
`pearlfan-rs` prints the USB ID in its README. They name the **retail product** — "a Pearl's
USB LED fan, PX5939". The identifier we searched by lives only inside the source files.

We were searching an index organised by *product identity* using the *device identity*.

What broke it was a different question, asked for a non-research reason: **"find me a fan I
can buy."** That forced the search into product space, where the drivers live. The
breakthrough was a reframe, and it arrived as a side effect of shopping for a replacement
after the original fan was destroyed.

The PEARL PX5939 name — the hinge of the whole thing — had already been found on 2026-09-02
as "lead B". We had it for three weeks and only ever pointed it at Pearl's dead FTP server,
never at GitHub.

## Why the find converted into a working fan in one slice

Two decisions made months of potential rework unnecessary.

**The unknown was isolated behind one seam from slice 4 onward.** D8 split the encoder into
known framing and unknown table; D13 and D16 kept that boundary as the evidence changed.
Slice 8 went further and *pre-tested* it with a deliberately trivial second conformance,
proving a new format would touch one type and nothing above it. At the time that looked like
architectural box-ticking on a project that would never reach hardware. It is the reason
slice 9 was one new type instead of a rewrite.

**The golden-test rule bought the first success.** "No bytes reach the fan until our bytes
match the reference byte for byte." Thirteen cable swaps across the project's history; the
first one that ever displayed anything was the first well-formed image the firmware received
from this repository. That was not luck.

## The mistake that repeated — four times

**We kept drawing firm conclusions from instruments nobody had validated.**

| Instrument | Its silence | What we concluded | Truth |
|---|---|---|---|
| `system_profiler SPUSBDataType` | empty output, exit 0 | "the bus is empty" | The tool is broken on this Mac |
| `log stream` on IOUSBHostFamily | no events on hotplug | "no enumeration" | Apple made those messages private |
| A glance at font-table byte patterns | high bytes all `0x2f`/`0x3f` | "the data is obfuscated" | Not enciphered at all; our layout guess was wrong |
| Search queries for `0c45:7701` | no results | "no prior art exists" | Two drivers existed; the query could not find them |

After the first one we adopted a rule for hardware: **never believe a negative result without
a known-good control in the same run.** It was the right rule. We simply never thought to
apply it to a *search query*, which is also an instrument.

The question we should have asked: **would this query find the thing if the thing existed?**
For `0c45:7701` the answer was no, and we could have known that on day one by checking how
similar projects name themselves.

## What was wasted, honestly

- **Slices 3 and 6 (probing).** No positive result, and the sweep erased the original fan's
  factory demo. The `A0` observation was real signal, but it could not be interpreted until
  pearlfan explained that `A0` is the header opcode. The clue only became meaningful in
  hindsight.
- **Slice 5 (vendor editor static analysis).** Excellent work, on the wrong device. It gave
  us the complete generation-2 protocol for `0x7160`, which our fan ignores. Retained as a
  selectable encoder; never needed.
- **Opening the head.** It destroyed the fan and gained nothing — but the board photo proved
  there was never an external EEPROM, so the "route 1b" chip-reading plan we mourned for a
  fortnight was never viable. The constraint cost us nothing.

## What was not wasted

`protocol-findings.md`. Every negative result was written down as carefully as every positive
one, so nothing was ever re-derived, and the record survived two closures and a hardware
replacement. It is also what made this retrospective possible.

## The human part

I closed the hardware chapter twice — once as "stalled", once as "the state space is
exhausted". Both times Willie refused to accept it. The second refusal produced the PEARL
lead, which is the thread that ends at those drivers.

He was also right three separate times against the documentation: pushing for one more sweep
found the vendor manual sitting unopened in his own download folder; questioning the second
closure produced the generation-2/3 insight; and plugging the fan in the way the manual
explicitly forbids tested the one configuration nobody had tried.

The pattern is worth naming, because it is the transferable lesson and it is not mine:
**when an authoritative-looking source says a thing is settled, test the thing.**

## For the next project

1. Treat a search query as an instrument, and validate it: would it find the thing if the
   thing existed? Search the way the target names *itself*.
2. Keep a known-good control for every negative result — hardware, tooling, or search.
3. Isolate the unknown behind one seam early, and test the seam before you need it.
4. Validate against a reference before touching the expensive oracle.
5. Write down what did not work, in as much detail as what did.
6. A second unit changes everything. The single hardest constraint in this project was
   "one fan, irreplaceable".
