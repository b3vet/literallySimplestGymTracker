# Roadmap & Progress Board

> **This is the live progress tracker.** Update the Status column as work ships. Status values: `⬜ Not started` · `🟦 In progress` · `✅ Shipped` · `⏸ Deferred`.
> Sequencing rule: ship the cheapest *existential* fix first → the *trust* signals that unlock recommendation → the *differentiator* that builds the moat → defer everything tied to a beginner pivot we haven't made.

## Already shipped (baseline — verified in repo, June 2026)
These are done; do **not** re-spec them. They are the foundation the roadmap builds on.

| Capability | Where | Notes |
|---|---|---|
| ✅ Set logging: reps / weight / **RIR** (no RPE) | `workout_dao`, `set_log_sheet.dart` | 2-tap + wheel; RIR is first-class |
| ✅ Rest timer + **Live Activity** | `rest_timer_controller`, `live_activity_controller` | Lock-screen countdown, accent-themed |
| ✅ Mid-workout exercise swap (with lineage) + durable skip + session-only inserts | `active_workout_controller`, `session_exercise_overrides` (DB v3-v5) | |
| ✅ **Drop sets** | DB v6 (`set_group`/`group_seq`), phone + watch | |
| ✅ Set-group primitive (**supersets-ready**) | DB v6 | Primitive exists; supersets not yet surfaced → SOW-08 |
| ✅ Progress charts / stats: **Epley 1RM**, volume, top-set trends | `stats_provider`, `stats_screen` (fl_chart) | Per-exercise progression; needs ≥2 sessions |
| ✅ History + summary + PR detection | `history_provider`, `summary_screen`, `PrDetector` | |
| ✅ kg/lb + per-exercise weight step | `weight.dart`, `settings_repository` | |
| ✅ **Apple Watch companion:** crown-driven reps/weight/RIR logging, HealthKit session, append-only sync | `ios/LSWatch Watch App/`, watch bridge schema v3 | The crown wedge is already real |
| ✅ Design system (Antonio / JetBrains Mono / IBM Plex Sans, 5-accent palette) | `app_theme.dart`, `DESIGN_SYSTEM.md` | |
| ✅ Onboarding + seeder | `features/onboarding/` | |

## Roadmap status board

| SOW | Feature | Phase | Tier | Status |
|---|---|---|---|---|
| [SOW-01](sow/SOW-01-plate-calculator.md) | Plate calculator (phone + watch) | 0 — Existential | Free | 🟦 Built — phone analyze+tests green; watch logic verified, pending Xcode build |
| [SOW-02](sow/SOW-02-data-export.md) | Data export (CSV/JSON) + native share bridge | 0 — Existential | Free | 🟦 Built — analyze+tests green (import-ready JSON: stable set/exercise/program ids); native `ls/share` (`ShareHandler.swift`) pending Xcode build |
| [SOW-02b](sow/SOW-02b-workout-summary-share.md) | Workout-summary share to friends (text + image card) | 0 — Existential | Free | 🟦 Built — analyze+tests green; share entry on post-workout **and** history detail; card overflow-tested at 1080×1350; pending Xcode build |
| [SOW-03](sow/SOW-03-logging-speed-and-rest-reliability.md) | Logging-speed audit + rest-timer survives app-switch/lock | 0 — Existential | Free | 🟦 Built — analyze+tests green (+12: rest force-kill persistence, finish/abandon-clears, sheet prefill); 1-tap repeat-last-set chip + last-set prefill (phone + watch); rest restored at launch, banner on RESUME tap (§4c no-new-UI); force-kill/Live-Activity device matrix (§8 M1–M11) + watch Swift pending hardware |
| [SOW-04](sow/SOW-04-warmup-calculator.md) | Warm-up set calculator | 1 — Trust/Table-stakes | Free | ⬜ Not started |
| [SOW-05](sow/SOW-05-sync-reliability-and-trust-claims.md) | Sync reliability hardening + "never overwrites" claim | 1 — Trust/Table-stakes | Free | ⬜ Not started |
| [SOW-06](sow/SOW-06-monetization-foundation.md) | Monetization foundation (entitlement, lifetime+annual, paywall) | 2 — Moat | Infra | ⬜ Not started |
| [SOW-07](sow/SOW-07-rir-auto-progression.md) | **RIR-derived auto-progression** (the paid differentiator) | 2 — Moat | Paid | ⬜ Not started |
| [SOW-08](sow/SOW-08-supersets.md) | Supersets (surface the set-group primitive) | 2 — Moat | Free | ⬜ Not started |
| [SOW-09](sow/SOW-09-hrv-readiness.md) | HRV readiness modifier | 3 — Surpass | Paid | ⬜ Not started |
| [SOW-10](sow/SOW-10-advanced-analytics.md) | Advanced analytics & trends | 3 — Surpass | Paid | ⬜ Not started |
| [SOW-12](sow/SOW-12-data-import.md) | Data import / restore (JSON round-trip) | 0/1 — Trust | Free | ⬜ Not started (committed next block) |

## Phase 0 — Existential (pre-launch, weeks, cheap)
**Goal:** be undeniably credible and undeniably free on day one. Nothing here is optional.
- **SOW-01 Plate calculator** — the single day-1 credibility gap; used at the rack; free; also on the watch.
- **SOW-02 Data export** — unlimited free core + full-history CSV/JSON export confirmed live at launch. The trust floor.
- **SOW-03 Logging speed + rest-timer reliability** — sub-3-tap logging audited in real gym conditions; the Live Activity rest timer must survive app-switch and lock (the #3 universal complaint).
- **Gate:** do not advance until logging speed + plate calculator are demonstrably best-in-class. If the crown adds friction, the whole speed claim collapses.

## Phase 1 — Trust & Expected table-stakes (first ~3 months)
**Goal:** clear every "recommendation-stopper" so r/weightroom can recommend us without an asterisk.
- **SOW-04 Warm-up set calculator** — low-complexity ramp (e.g. 50/70/85/100%); present in praised baselines.
- **SOW-05 Sync reliability hardening + trust claims** — load-test the idempotent merge; ship the testable "your phone is the source of truth; the watch never overwrites it" claim.
- *(Progress charts already shipped — confirm they stay free when monetization lands; see SOW-06.)*
- *(RIR field already shipped free — confirm it stays free and skippable.)*

## Phase 2 — The differentiator & the moat (~6 months, race against Alpha ⏰)
**Goal:** ship the paid wedge and the monetization to support it, before Alpha ships a watch.
- **SOW-06 Monetization foundation** — entitlement model, $29.99 lifetime + ~$19.99 annual, no monthly, the basic/smart paywall seam. (Build before SOW-07 so there's something to gate.)
- **SOW-07 RIR auto-progression (PAID)** — the headline: when logged RIR drifts >2 at constant load across 2+ sessions, surface one rationale-bearing nudge to add ~2.5-5%. The loved Alpha mechanic, delivered on the wrist where no one else can.
- **SOW-08 Supersets** — surface the existing set-group primitive; a "match-and-surpass" feature lifters ask for that fits minimalism.
- **Gate:** Phase 2 is the contested investment — parity with Alpha on mobile, defensible only on the watch and only until Alpha ships one. Build it, but build the free table-stakes excellence first.

## Phase 3 — Surpass / fast-follow (12-18 months, conditional)
**Goal:** open the next unoccupied lane before the platform giants normalize it.
- **SOW-09 HRV readiness modifier (PAID)** — read HealthKit HRV against a rolling baseline; one bounded pre-workout adjustment. The move neither Hevy nor Fitbod makes. *Accelerate if Apple ships its rumored AI health coach; defer if Hevy Trainer adoption proves low.*
- **SOW-10 Advanced analytics & trends (PAID)** — the willing-to-pay upgrade for data nerds; additive only.

## Deferred (build only on a deliberate pivot to beginner acquisition)
⏸ In-app program library · exercise video library · **in-app social feed** (following / likes / comments) · computer-vision form check · Android · Wear OS · cellular-standalone watch parity. Each is bloat for the target segment or a losing fight on a rival's turf. **The discipline of not building these is the strategy.**

> **Not deferred — encouraged:** *outbound* "share my workout to a friend" (SOW-02b) is the **opposite** of an in-app feed. It's the word-of-mouth/viral loop the strategy says we lack, with none of the feed's bloat. Share-to-chat ≠ social feed.

## Schema & build-order coordination (read before implementing)
Several SOWs were written independently and each assumes it owns the *next* schema version. They cannot all be right — reconcile at build time:

- **SQLite DB version (currently v6).** SOW-08 (supersets), SOW-09 (HRV), and SOW-10 (advanced analytics) each add columns and each drafted themselves as "v7"; SOW-05 needs a column only conditionally. **Rule: whichever ships first takes v7, the next v8, etc.** Keep migrations additive (nullable columns, no backfill), mirroring `schemaV6Up`. Bump `_dbVersion` in `lib/core/db/database.dart` once per shipped migration.
- **Watch bridge / Pigeon schema (currently v3).** SOW-07 (adds a progression-suggestion field) and SOW-08 (adds superset fields) each drafted "v4." **Same rule: first to ship is v4, next v5.** All new snapshot fields must be optional so older watch builds ignore them (forward-compat, as `skipped`/`dropCount` already are).
- **`session_exercise_overrides` mirroring.** Any new `program_exercises` column that must survive a mid-session swap also needs a mirror column on `session_exercise_overrides` (the pattern `drop_count` followed in v6) — SOW-08 calls this out explicitly.
- **Two real bugs the SOWs surfaced (fold into their builds):** (1) the rest timer is in-memory only, so it's lost on force-kill — persist `endsAt` to `shared_preferences` (SOW-03). (2) `editSet`/`deleteSet` apply unconditionally with no last-writer-wins timestamp guard, so the documented LWW reconciliation isn't actually enforced on the phone (SOW-05). Neither causes data *loss* today, but both undercut the reliability claim.

## Decision-condition triggers to watch
- **Alpha Progression ships an Apple Watch app** → the watch-RIR moat narrows to execution quality; accelerate SOW-07 hard.
- **Apple ships an AI health coach** → SOW-09 HRV becomes table-stakes; accelerate.
- **We decide to chase beginner volume** → program library + video library flip from deferred to existential.
- **Hevy Trainer adoption proves high** → revisit whether the AI nudge (SOW-07) needs to ship earlier/bigger.
