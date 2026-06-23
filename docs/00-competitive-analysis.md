# Competitive Analysis (condensed)

> Distilled from the June 2026 competitive & market analysis. This is the human-readable summary; the full report — with per-rival detail, sentiment quotes, and citations — is at [competitive-analysis-full-report.md](competitive-analysis-full-report.md).

## The market in one picture
- **Size:** global fitness-app market ~$12.1B (2025) → ~$33.6B (2033), ~13.4% CAGR. **iOS = ~53% of US revenue** and growing faster than Android — our iOS-first bet is where the paying users are.
- **The field splits into four camps:**

| Camp | Apps | Competes on |
|---|---|---|
| Fast loggers | Strong, FitNotes, Setgraph, Liftin' | Sub-3-second logging, no coaching — **our home turf** |
| Program / library | Hevy, Jefit, Boostcamp | Big libraries, social feed, free programs |
| AI generators | Fitbod, GymStreak | "We pick your workout" |
| Auto-regulation premium | Alpha Progression, RP Hypertrophy, Juggernaut, Dr. Muscle, Caliber | RIR/mesocycles — but broken gym-floor UX |

**The empty quadrant:** every app with great RIR (Alpha, RP, Dr. Muscle) has no real Apple Watch; every app with a great watch (Strong, Setgraph, GymStreak) has no real RIR. **Nobody is fast + minimalist + RIR-native + watch-first. That intersection is ours to take.**

## Per-rival cheat sheet

| App | Price | Platforms / Watch | RIR | Standout | Fatal flaw (our opening) |
|---|---|---|---|---|---|
| **Strong** | $4.99/mo · $99.99 life | iOS/Android/Watch (Pro-gated) | RPE (Pro) | Fastest logger, brand | Stalled; **Watch sync data-loss bug**; basics paywalled |
| **Hevy** | $2.99/mo · $74.99 life | all + Wear OS + web | RPE only (decorative) | Best free tier, social loop, cheapest lifetime | RIR is logged but **not acted on**; "overbuilt over time" |
| **Jefit** | $12.99/mo · $69.99/yr | all + Wear OS + web | None | 1,400+ exercises, deepest analytics | **Cluttered, crashes, 286MB** — the bloat cautionary tale |
| **Fitbod** | $15.99/mo | Apple-only | None | AI generation at scale, clean UX | Cold-start cliff (10-15 workouts); advanced lifters distrust it |
| **Boostcamp** | Free · $59.99/yr | iOS/Android/Watch | **Free** | 11k free programs + free RIR | **Free RIR undercuts our moat**; shallow watch |
| **FitNotes** | $0 (Android) | Android + iOS(FN2)/Watch | FN2 watch only | Free, "indestructible" | Dated, no cloud sync; FN2 watch closes between sets |
| **Setgraph** | ~$30/yr · ~$120 life | iOS-primary/Watch | No | Closest minimalist twin; best Live Activity | No RIR, no program structure, thin free tier |
| **Alpha Progression** | $9.99/mo · $59.99/yr | iOS/Android · **no Watch** | **Yes (loved)** | Best RIR auto-progression, 4.9★ | **No Apple Watch** — the only reason our wedge is open |
| **StrongLifts** | $11.99/mo · $59.99/yr | iOS/Android/Watch | No | Deepest "leave phone in locker" watch | **Revoked its lifetime (Jan 2026)** → "bait and switch" |
| **GymStreak** | $12.99/mo · $59.99/yr | iOS/Android/Watch | No | Feature-rich watch, slick UI | Billing "scam" (33.5/100 legitimacy); fatigue-blind AI |
| **Liftin'** | $24.99/yr | Apple-only | No (RPE) | Philosophical twin, deep Strava sync | RPE not RIR, no auto-progression, tap-not-crown |
| **Caliber** | Free · ~$200/mo | iOS/Android · **no Watch** | No | Human coaching (4.9 Trustpilot) | No watch, no auto-regulation on free |
| **RP Hypertrophy** | $34.99/mo | iOS/Android/PWA · **no Watch** | **Yes (0-4)** | Most credentialed RIR science | **No offline, no timer, no plate calc, no watch** (2.8★) |
| **Juggernaut AI** | $34.99/mo | iOS/Android · **no Watch** | No | High-ceiling powerlifting | **No Apple Health, no plate calc, no timer**; billing trap |
| **Dr. Muscle** | $48.99/mo | iOS/Android/Watch | **Yes (DUP)** | AI DUP pioneer, has a watch | Dated 2016 UI, single-method, top-of-category price |

## Where we're behind ("places we may be back")
1. **Plate calculator** — the one *existential* day-1 gap. Used at the rack; everyone credible ships it; its absence shows up in negative reviews (Juggernaut, RP). **We don't have one.**
2. **Data export (CSV)** — a trust signal; absence is a recommendation-stopper on r/weightroom. **We don't have one.**
3. **Warm-up set calculator** — cheap, expected, present in Strong/Liftin'. **We don't have one.**
4. **Monetization** — we have *zero* infrastructure; rivals monetize on lifetime/annual.
5. **No social viral loop + iOS-only** — the real strategic risk: our acquisition funnel is the slow generic-ASO + word-of-mouth path Hevy avoided by building a feed.

## Where we win ("where LS can improve / surpass")
- **Crown-driven logging is unoccupied.** No rival uses the Digital Crown to dial weight/reps/RIR. *We already ship this.* Market it as the fastest logging anywhere.
- **RIR + watch = empty quadrant**, ours for ~12 months until Alpha ships a watch.
- **Reliability as a claim** — our append-only, phone-is-source-of-truth sync structurally *cannot* reproduce Strong's data-loss bug. "The watch never overwrites your phone."
- **Trust** — no betrayal record. Free core + honored lifetime = a moat the incumbents already spent.
- **RIR auto-progression done where no one can** — Alpha's loved engine, on the wrist.

## What we should deliberately NOT build
Social feed, exercise video library, in-app program library (we're program-*based* — the user brings the program), full AI generator, computer-vision form check, Android, Wear OS. Each is bloat for our segment or a losing fight on Hevy/Fitbod's turf. The discipline of *not* building these is the strategy.

## Emerging trends (and our posture)
- **AI coaching** is mostly "heuristics in a costume" (even Hevy's RIR is decorative). → Ship one narrow RIR-aware nudge; decline the generator.
- **Recovery-aware HRV programming** — nobody does it at a minimalist price. → The unoccupied future lane (Phase 3).
- **Sensor/auto rep-detection** (Train Fitness) — immature today, but the one trend that could erode "fastest *manual* logger." → Watch, don't build.
- **Apple's rumored AI health coach** — would normalize HRV-to-intensity. → Argues for shipping our HRV modifier while it still differentiates.
