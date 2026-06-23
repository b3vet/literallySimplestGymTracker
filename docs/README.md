# LS Gym Track — Product Docs (Source of Truth)

This folder is the **single source of truth** for LS Gym Track's strategy, roadmap, and progress. It is derived from a competitive/market analysis of 15 rivals (June 2026) and grounded in the actual codebase.

> **The app's one-line bet:** be the *fastest, most trustworthy* strength logger on iOS, with effort-aware **RIR** intelligence delivered on the **Apple Watch crown** — minimalist by discipline, honest by design, additive by monetization. Own the one empty market quadrant (fast + minimalist + RIR-native + watch-first) before the one rival who could copy it (Alpha Progression) ships a watch.

## How to use these docs
- **Read [01-strategy-and-positioning.md](01-strategy-and-positioning.md) first** — the "why" behind every decision. Positioning, the trust pillar, monetization philosophy, and the competitive clock.
- **[02-roadmap.md](02-roadmap.md) is the live progress board** — update its status table as work ships. This is what to check to know "where are we?"
- **[00-competitive-analysis.md](00-competitive-analysis.md)** — the condensed rival landscape: what each competitor has, where we're behind, where we win. (Full 11k-word report: [competitive-analysis-full-report.md](competitive-analysis-full-report.md).)
- **[sow/](sow/)** — one Statement of Work per feature, sequenced to be built one at a time. Each follows [sow/SOW-00-template.md](sow/SOW-00-template.md).

## Document index

| Doc | Purpose |
|---|---|
| [01-strategy-and-positioning.md](01-strategy-and-positioning.md) | Strategic verdict, positioning claims, ASO, monetization model, risks, the Alpha clock |
| [00-competitive-analysis.md](00-competitive-analysis.md) | Condensed competitor landscape + gap analysis |
| [02-roadmap.md](02-roadmap.md) | Phased roadmap + **live progress board** |
| [sow/SOW-00-template.md](sow/SOW-00-template.md) | The SOW format every feature doc follows |
| [sow/](sow/) | SOW-01 … SOW-10 — implementable feature specs |

## The non-negotiables (read before building anything)
1. **Free core forever.** Unlimited logging + data export are never gated. This is the acquisition gate Hevy reset to zero; gating it is predicted death.
2. **Trust is a feature.** No retroactive paywalls, ever. A lifetime purchase, once sold, is honored forever and never gates core logging. (StrongLifts revoked its "lifetime" in Jan 2026 and got branded "bait and switch" — that is the exact mistake to never make.)
3. **Market speed, not "the watch."** The Apple Watch is the #5-of-5 reason people pick a tracker. The crown is the *delivery vehicle* for the #1 reason (logging speed) and the unoccupied one (wrist-RIR). Lead App Store copy with speed + RIR, not "Apple Watch support."
4. **Minimalism is a discipline.** Every feature we *decline* (social feed, video library, AI generator, big exercise library) is part of the strategy. Intelligence must stay a single invited nudge, never a coaching surface.
5. **The clock is real.** Alpha Progression is the only rival that could match the watch+RIR wedge; it has a watch on its roadmap and has shipped nothing. Phase 2 races that.

## Provenance
- Source: competitive & market analysis of 15 rivals, June 2026 — full report at [competitive-analysis-full-report.md](competitive-analysis-full-report.md).
- Codebase facts in the SOWs were verified against the live repo (DB schema v6, Riverpod tri-layer features, watch app schema v3).
