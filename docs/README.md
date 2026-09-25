# LedFan — documentation set

A macOS app that displays a typed message on a USB LED persistence-of-vision fan.

These documents are the **authoritative specification**. Where the checked-in Swift and
these documents disagree, the documents win.

## Where the project stands (2026-09-25)

Working. The app builds warning-free in Swift 6 with strict concurrency, is fully tested,
previews a message legibly in mixed case, scrolls long ones, remembers eight slots, and
publishes all eight to the real fan over the PearlFan protocol with every report verified
against the fan's echo. The protocol was found in September in two public drivers for the
fan's retail model; `protocol-findings.md` holds the byte-level map and the log of the
first sends.

## Read in this order

| Document | What it settles |
|---|---|
| [`current-state.md`](current-state.md) | **Start here.** What the app does, what is deliberately not there, and how the hardware question was settled |
| [`onboarding.md`](onboarding.md) | Prerequisites, commands, guardrails |
| [`brief.md`](brief.md) | Goal, constraints, the three milestones and their outcomes |
| [`decisions.md`](decisions.md) | **Architect decisions. Overrides older docs.** |
| [`retrospective.md`](retrospective.md) | How the project actually got solved, and the mistakes that repeated |
| [`architecture.md`](architecture.md) | Module boundaries, contracts, concurrency model |
| [`features.md`](features.md) | Feature set with acceptance criteria, ticked only where demonstrated |
| [`design.md`](design.md) | UI structure, design tokens, motion, accessibility |
| [`testing.md`](testing.md) | Test strategy and what is covered |
| [`hardware.md`](hardware.md) | The device, how to reach it, what is proven vs unknown |
| [`protocol-discovery.md`](protocol-discovery.md) | The routes tried to find the wire format, and why each is closed |
| [`protocol-findings.md`](protocol-findings.md) | The full experiment log, including negatives, ending with the summary for a later reader |
| [`briefs/`](briefs/) | Per-slice work briefs from the architect |
| [`reports/`](reports/) | Per-slice acceptance reports from the build session, each with "where the brief was wrong" |

## Ground rules for the build session

1. **Read `hardware.md` and the end of `protocol-findings.md` before touching transport
   code or the fan.** Twelve cable swaps and one erased factory demo are recorded there.
2. **The wire protocol is unknown, and the app never writes to the head (D9).** Blind
   writes are a `Tools/` activity, done with the owner at the fan and asking for it.
3. **Every acceptance box is ticked by something a person can look at**, not by the code
   compiling. Screenshots and frame strips live in `reports/images/`.
4. Engineering standards live in [`../CLAUDE.md`](../CLAUDE.md) at the repository root.
