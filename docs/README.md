# LedFan — documentation set

A macOS app that displays a typed message on a USB LED persistence-of-vision fan.

These documents are the **authoritative specification**. Where the checked-in Swift and
these documents disagree, the documents win — see `current-state.md` for why.

## Read in this order

| Document | What it settles |
|---|---|
| [`onboarding.md`](onboarding.md) | **Start here.** Prerequisites, first tasks, commands, guardrails |
| [`brief.md`](brief.md) | Goal, constraints, what done looks like |
| [`hardware.md`](hardware.md) | The device, how to reach it, what is proven vs unknown |
| [`architecture.md`](architecture.md) | Module boundaries, contracts, concurrency model |
| [`features.md`](features.md) | Feature set with acceptance criteria |
| [`design.md`](design.md) | UI structure, design tokens, accessibility |
| [`testing.md`](testing.md) | Test strategy and what must be covered |
| [`protocol-discovery.md`](protocol-discovery.md) | How to reverse-engineer the wire format |
| [`current-state.md`](current-state.md) | Inventory of existing code and its trust level |
| [`decisions.md`](decisions.md) | **Architect decisions. Overrides older docs.** |
| [`briefs/`](briefs/) | Per-slice work briefs from the architect |
| [`reports/`](reports/) | Per-slice acceptance reports from the build session |
| [`protocol-findings.md`](protocol-findings.md) | Running log of protocol experiments, including negatives |
| [`reports/`](reports/) | One report per work slice, for architect review. Newest is the current state of play |

## Ground rules for the build session

1. **Read `hardware.md` before touching transport code.** It records findings that cost
   real time to establish, including two conclusions that turned out to be wrong.
2. **The wire protocol is unknown.** No amount of Swift fixes that. The app must be useful
   and fully testable without it — see the simulated transport in `architecture.md`.
3. **Nothing in `LedFan/` has ever been compiled.** Treat the first successful build as
   step one, not as a regression.
4. Record protocol discoveries in `protocol-findings.md` (create it) as they happen.
5. Engineering standards live in [`../CLAUDE.md`](../CLAUDE.md) at the repository root.
