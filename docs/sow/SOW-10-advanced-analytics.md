# SOW-10 — Advanced Analytics & Trends

> **Status:** ⬜ Not started · **Phase:** 3 · **Tier:** Paid
> **Owner:** berke · **Est. size:** M
> **Strategic rationale:** The willing-to-pay upgrade for the data-nerd segment — *additive only*. Matches Jefit/Hevy analytics depth selectively, surpasses by being focused + beautiful and by surfacing **RIR-trend analytics** the decorative-RIR rivals (Hevy, Strong, Boostcamp) structurally can't. Closes the "deepest analytics" line in [00-competitive-analysis.md](../00-competitive-analysis.md) without becoming the Jefit-style bloat we position against. See the additive-monetization seam in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md).

Every SOW in this folder follows this structure. Keep it grounded in real files (cite `lib/...` paths), match the existing architecture (Riverpod tri-layer, sqflite migrations, the design system), and respect the non-negotiables in [README.md](../README.md).

---

## 1. Goal & Constraints

- **What this delivers** (user-visible):
  - A new **paid "Advanced" analytics surface** layered on top of the existing free Stats screen — *added*, never replacing the free charts.
  - A **focused, minimalist set** of advanced views: per-muscle-group volume over time, a training-frequency calendar heatmap, RIR-trend analytics (are you training closer to failure over time?), an estimated-1RM leaderboard across exercises, and a PR timeline.
  - Gated behind the SOW-06 entitlement; a clean, honest upsell when locked (never a teaser that hides previously-free data).

- **Why now:** Phase 3 ("Surpass"). The free core (fast logging, free basic charts, free RIR field) is established and stays free. This is the *additive* analytics layer the serious/data-nerd niche will pay for — and the one place we can show RIR-trend intelligence that the decorative-RIR field rivals cannot.

- **Hard constraints (non-negotiable):**
  - **No retroactive paywall.** The currently-free charts — per-exercise **top-set weight**, **total volume**, **Epley est-1RM**, and the **30-day trend delta** in `lib/features/stats/presentation/stats_screen.dart` (`StatsMetric.topSet/volume/est1rm`, `trendDelta` in `lib/features/stats/application/stats_provider.dart`) — **STAY FREE, unchanged, and unguarded.** Moving any of them behind the entitlement is the exact StrongLifts "bait and switch" pattern we position against (README non-negotiable #2). This SOW *only ADDS* new views.
  - **Minimalism discipline.** Ship the focused set below; do **not** build a Jefit-style analytics maze. Every advanced view must earn its place against the "is this a coaching surface?" test.
  - **No new charting dependency.** Reuse `fl_chart` (already in the tree, used by `stats_screen.dart`) and the design tokens (`LsType`, `LsAccent`/`t.accent`, `LsGap`/`LsSpace`, `LsRadius.r3`, `LsCard`, `LsSheet`).
  - **Offline / first-party.** All aggregation is local SQL over the existing sqflite DB. No network, no analytics SDK.

- **Non-goals (deliberately NOT in this SOW):**
  - No CSV/JSON of analytics (that's data export — SOW-02).
  - No coaching recommendations or auto-progression (that's SOW-07); analytics *describe*, they do not *prescribe*.
  - No MEV/MAV/MRV *prescription engine* — at most a passive volume-landmark reference band, opt-in and labeled as a heuristic (see §3 decision 7), never a nag.
  - No new chart type invented from scratch; only line / bar / scatter / calendar-grid built from `fl_chart` primitives.
  - No watch surface — analytics are a phone-only reflective surface (watch is for logging speed).

## 2. Competitive context

| Rival | What they ship | Where they fall short (our opening) |
|---|---|---|
| **Jefit** | Deepest analytics in the category | "Cluttered, crashes, 286MB" — the bloat cautionary tale. We *match depth selectively* and *surpass on focus + beauty*. |
| **Hevy** | Solid volume/PR analytics, good free tier | RIR/RPE is **logged but decorative** — they never turn it into a trend. We surface **RIR-trend analytics** they can't. |
| **Strong** | Per-exercise charts, records | Basics paywalled; RPE Pro-gated and not analyzed. |
| **Boostcamp** | Free RIR | Shallow analytics; RIR free but not trended. |
| **Alpha Progression** | Good progression analytics | No watch; analytics tied to its coaching loop. |

- **What "match" looks like:** per-muscle-group volume, frequency heatmap, PR history, cross-exercise 1RM ranking — table-stakes for "deep analytics."
- **What "surpass" looks like:** (1) **RIR-trend analytics** — average logged RIR per muscle/exercise over time, answering "am I training closer to failure?" — a question only an app that *acts on* RIR can pose; (2) the design system makes five focused views feel premium where Jefit's twenty feel like a spreadsheet.

## 3. Locked decisions

### 3a. The free-vs-paid table (the trust contract)

| Chart / metric | Where it lives today | Tier after this SOW | Note |
|---|---|---|---|
| Per-exercise **top-set weight** progression | `stats_screen.dart` (`StatsMetric.topSet`) | **FREE (unchanged)** | Never gated. |
| Per-exercise **total volume** progression | `stats_screen.dart` (`StatsMetric.volume`) | **FREE (unchanged)** | Never gated. |
| Per-exercise **Epley est-1RM** progression | `stats_screen.dart` (`StatsMetric.est1rm`) | **FREE (unchanged)** | Never gated. |
| **30-day trend delta** pill + BEST footer | `stats_provider.dart` `trendDelta()` | **FREE (unchanged)** | Never gated. |
| Exercise selector + metric segmented control | `stats_screen.dart` | **FREE (unchanged)** | Never gated. |
| **Per-muscle-group volume** over time | *new* | **PAID** | New view (needs muscle taxonomy, §5). |
| **Training-frequency calendar heatmap** | *new* | **PAID** | New view. |
| **RIR-trend analytics** (avg RIR over time, per exercise/muscle) | *new* | **PAID** | New view — the differentiator. |
| **Estimated-1RM leaderboard** (cross-exercise ranking) | *new* | **PAID** | New view. |
| **PR timeline** (chronological PR feed) | *new* | **PAID** | New view. |
| **Volume-landmark reference band** (MV/MEV-style, opt-in heuristic) | *new* | **PAID** | New, off by default, labeled heuristic. |

> **Invariant:** the first five rows are the free surface that exists today. This SOW does not touch their tier, their code paths, or their visibility. A reviewer must be able to confirm (acceptance criterion §7) that a non-entitled user sees **every** free chart exactly as before.

### 3b. Engineering decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Scope of advanced views | **Five focused views + one opt-in band** (per-muscle volume, frequency heatmap, RIR-trend, 1RM leaderboard, PR timeline; volume-landmark band opt-in) | Match depth selectively; refuse the Jefit maze. |
| 2 | Where advanced views live | A **separate "Advanced" section** appended below the existing free cards on the Stats screen, behind a single entitlement gate | Free charts stay visually first and untouched; the paid surface is clearly additive. |
| 3 | Muscle-group source | **Add a muscle taxonomy to `exercises`** (`primary_muscle`, `muscle_group`) via DB **v7**, seeded for known exercises, `NULL`/`other` fallback | `exercise.dart` has no muscle field today; per-muscle volume is impossible without it. Nullable + fallback keeps it non-breaking. |
| 4 | 1RM formula reuse | **Reuse the existing Epley** (`w * (1 + reps/30)`) from `stats_provider.dart` | One 1RM definition app-wide; no second "best 1RM" number that contradicts the free chart. |
| 5 | RIR-trend definition | **Average logged `rir` per session, plotted over time**, per exercise and aggregated per muscle group; lower trend = training closer to failure | `rir` is a first-class column on `workout_sets`; this is a pure aggregation. |
| 6 | Heatmap granularity | **Calendar grid of completed sessions per day** (GitHub-style intensity by set-count), last ~16 weeks | Cheap, glanceable, reuses `started_at`/set counts; no new data. |
| 7 | Volume landmarks | **Opt-in passive reference band only** (no prescription, no nag), labeled "heuristic — not coaching" | Minimalism + non-goal: analytics describe, never coach. Honors README non-negotiable #4. |
| 8 | Gating mechanism | **Single `entitlementProvider` (from SOW-06)**; the Advanced section reads it and renders the upsell when locked | Centralized seam so SOW-06 owns purchase/restore; SOW-10 only *reads* the flag. |
| 9 | Charting library | **`fl_chart` only** (already used by `stats_screen.dart`) | No new dependency; consistent visual language. |
| 10 | Empty/insufficient-data behavior | Mirror the free chart's "INSUFFICIENT DATA — LOG AT LEAST 2 SESSIONS" pattern per view | Consistent with `stats_screen.dart`. |

## 4. Design & UX

**Screens/sheets touched:** `lib/features/stats/presentation/stats_screen.dart` (append an Advanced section below the existing free cards — the existing `ListView` children stay first and unchanged). New presentation widgets under `lib/features/stats/presentation/advanced/`.

**Design-system mapping:** reuse `LsCard` (`LsPad.cardSpacious` / `LsSpace.cardHero`), `EyebrowLabel`, `LsType.displayHero`/`displayM`/`monoMeta`/`monoMicro`, `t.accent.accent` for series + `t.surface.border` for gridlines/hairlines, `LsRadius.r3` for the segmented control, exactly as the free cards do today. The five accents stay theme-driven via `LsTheme.of(context)`.

**Flow:** the Stats screen renders the free cards first (no change), then — at the bottom — an **"ADVANCED"** eyebrow header followed by the gated section.

**Locked (non-entitled) state — honest upsell, no hidden free data:**

```
┌──────────────────────────────────────────┐
│  [ free top-set / volume / 1RM cards …  ] │  ← unchanged, always visible
├──────────────────────────────────────────┤
│  ADVANCED                          🔒      │
│  ┌────────────────────────────────────┐   │
│  │ Per-muscle volume · RIR trends ·   │   │
│  │ frequency heatmap · 1RM board · PR │   │
│  │ timeline.                          │   │
│  │                                    │   │
│  │ One-time purchase, honored forever.│   │
│  │        [  UNLOCK ADVANCED  ]       │   │  → opens SOW-06 paywall
│  └────────────────────────────────────┘   │
└──────────────────────────────────────────┘
```

**Unlocked state — the advanced surface (a sub-tab strip inside the Advanced card):**

```
ADVANCED                                    ✓ UNLOCKED
┌──────────────────────────────────────────────────────┐
│ [VOLUME] [FREQUENCY] [RIR] [1RM] [PR]                 │  ← LsRadius.r3 segmented, like _MetricSegmented
├──────────────────────────────────────────────────────┤
│  PER-MUSCLE VOLUME · 8 WEEKS                          │
│   CHEST   ███████████████████  12,400 KG   +6%       │
│   BACK    █████████████████    11,050 KG   +2%       │
│   LEGS    ██████████████████████ 14,900 KG  −1%      │
│   ...     (stacked bar over weeks via fl_chart)      │
└──────────────────────────────────────────────────────┘
```

```
RIR TREND · BENCH PRESS                       AVG 1.8 RIR
┌──────────────────────────────────────────────────────┐
│  4 ┤                                                  │
│  3 ┤   •                                              │
│  2 ┤        •      •            ← trending down =      │
│  1 ┤              •     •  •      closer to failure    │
│  0 ┤                       •                           │
│    └──────────────────────────────────────────────    │
│      May        Jun        (line via fl_chart)        │
│  "Lower = closer to failure. You're 1.2 RIR closer    │
│   than 6 weeks ago." (descriptive, not coaching)      │
└──────────────────────────────────────────────────────┘
```

```
FREQUENCY · LAST 16 WEEKS              42 SESSIONS
┌──────────────────────────────────────────────────────┐
│  M  ▢ ▣ ▤ ▦ ▢ ▣ ▦ ▢ ▣ ▤ ▦ ▢ ▣ ▦ ▢ ▣                  │
│  T  ▣ ▢ ▦ ▢ ▣ ▤ ▢ ▦ ▢ ▣ ▢ ▤ ▦ ▢ ▣ ▢                  │  ← intensity = sets that day
│  W  ▤ ▦ ▢ ▣ ▦ ▢ ▣ ▢ ▤ ▦ ▢ ▣ ▢ ▦ ▢ ▣                  │     (t.accent alpha ramp)
│  ...                                                  │
└──────────────────────────────────────────────────────┘
```

```
EST 1RM LEADERBOARD                         (Epley)
┌──────────────────────────────────────────────────────┐
│  1  DEADLIFT      180 KG     ↑ PR 2d ago              │
│  2  SQUAT         150 KG                              │
│  3  BENCH PRESS   110 KG     ↑ PR 9d ago              │
│  ...   (ranked list, accent for fresh PRs)           │
└──────────────────────────────────────────────────────┘
```

```
PR TIMELINE
┌──────────────────────────────────────────────────────┐
│  ● JUN 21 · DEADLIFT · 180 KG est 1RM  (+5)          │
│  │ JUN 14 · BENCH    · 110 KG est 1RM  (+2.5)        │
│  ● JUN 02 · SQUAT    · 150 KG est 1RM  (+5)          │
│  ...  (chronological, newest first)                  │
└──────────────────────────────────────────────────────┘
```

**Watch:** none. Analytics are a phone reflective surface; the watch stays a logging instrument.

## 5. Data & schema changes

**Migration: DB v6 → v7** — add the muscle taxonomy needed for per-muscle volume. Mirror the cumulative pattern in `lib/core/db/migrations.dart` and bump `_dbVersion` to `7` in `lib/core/db/database.dart` (wire `schemaV7Up` into both `onCreate` and the `if (oldVersion < 7)` branch of `onUpgrade`, exactly like v6).

```dart
/// v7: muscle taxonomy for advanced per-muscle-group analytics (SOW-10).
///
/// `exercises` has no muscle metadata today (see exercise.dart), so per-muscle
/// volume is impossible without it. Both columns are nullable so the migration
/// is non-breaking: existing rows keep working, and any exercise without a
/// mapping aggregates under the 'other' bucket at query time. A best-effort
/// seed pass maps the known seeded exercise names to a muscle group; user-
/// created exercises stay NULL until (optionally) edited.
const schemaV7Up = <String>[
  "ALTER TABLE exercises ADD COLUMN muscle_group TEXT",   // e.g. 'chest','back','legs','shoulders','arms','core','other'
  "ALTER TABLE exercises ADD COLUMN primary_muscle TEXT", // finer-grained, optional
  "CREATE INDEX IF NOT EXISTS idx_exercises_muscle ON exercises(muscle_group)",
];
```

- **Seeding:** a one-time best-effort `UPDATE exercises SET muscle_group = ? WHERE name = ? COLLATE NOCASE` pass over the onboarding seed names (mirror the seeder under `lib/features/onboarding/`). Unmapped → `NULL` → bucketed as `'other'` in queries. Editing an exercise's muscle group is **out of scope** here (can be a tiny follow-up); the seed + `'other'` fallback is enough to ship the view.
- **`exercise.dart` domain:** extend `Exercise` with nullable `muscleGroup` / `primaryMuscle` (read from the new columns in `fromRow`, written in `toRow`). Existing constructors keep working since both are optional.
- **No change** to `workout_sets` — `rir`, `weight`, `reps`, `logged_at`, `set_group` already carry everything the RIR-trend, frequency, 1RM, and PR analytics need.
- **Settings/flags:** add a single bool pref `settings.analytics_volume_landmarks` (decision 7, opt-in band; default `false`) via the `SettingsRepository` pattern in `lib/core/settings/settings_repository.dart` (new `_kVolumeLandmarks` key + read/write, mirroring `liveActivityEnabled`).
- **Entitlement (from SOW-06):** SOW-10 **consumes** a read-only `entitlementProvider` (a `Provider<bool>` exposing "has advanced/paid entitlement"). SOW-06 owns the purchase/restore/storage; if SOW-06 has not landed, stub `entitlementProvider` to return `false` and the Advanced section renders the locked upsell. **No watch bridge / Pigeon change.**

## 6. Implementation plan

Ordered by layer. New code lives under `lib/features/stats/` to keep it beside the existing free stats.

1. **`data/` (DB) — `lib/core/db/migrations.dart` + `lib/core/db/database.dart`:** add `schemaV7Up`, bump `_dbVersion` to 7, wire into `onCreate` + `onUpgrade`. Add the seed-mapping pass (new `lib/features/stats/data/muscle_seed.dart` map of name→group, applied post-migration or via the onboarding seeder).
2. **`domain/` — `lib/features/programs/domain/exercise.dart`:** add nullable `muscleGroup`/`primaryMuscle` to `Exercise.fromRow`/`toRow`/constructor.
3. **`data/` (DAO) — new `lib/features/stats/data/analytics_dao.dart`** (or extend `WorkoutDao` in `lib/features/workout/data/workout_dao.dart` via an extension, mirroring `WorkoutDaoOverrides`). New aggregation queries, all over completed sessions only (`s.status = 'completed'`, like `exerciseProgressionProvider`):
   - `muscleVolumeByWeek({int weeks})` → `SUM(weight*reps)` grouped by `COALESCE(e.muscle_group,'other')` and ISO week bucket of `started_at`.
   - `sessionFrequency({int weeks})` → completed-session count + set-count per calendar day.
   - `rirTrendForExercise(exerciseId)` → `AVG(rir)` per session over time; `rirTrendByMuscle(group)` aggregated variant.
   - `estimated1RMLeaderboard()` → per exercise, `MAX(weight*(1+reps/30.0))` (Epley, reused) ranked desc.
   - `prTimeline()` → chronological list of new est-1RM PRs (a running-max scan over time, reusing the `PrDetector`/`historicalMaxWeight` ideas in `workout_dao.dart`).
4. **`application/` (provider) — extend `lib/features/stats/application/stats_provider.dart`** (or a sibling `advanced_stats_provider.dart`): `FutureProvider`s wrapping each DAO method, chaining invalidation through `workoutDaoProvider`/`programDaoProvider` exactly as `exerciseProgressionProvider` does. Reuse the existing Epley line and `trendDelta()` helper for per-muscle deltas. **Do not modify** `exerciseProgressionProvider`, `loggedExercisesProvider`, or `trendDelta` — the free path is frozen.
5. **`application/` — entitlement read:** import the `entitlementProvider` (SOW-06). Add a local fallback stub returning `false` if SOW-06 is not yet merged, isolated so it's a one-line swap when SOW-06 lands.
6. **`presentation/` — new `lib/features/stats/presentation/advanced/`:** `advanced_section.dart` (the gate + segmented strip), plus one widget per view (`muscle_volume_card.dart`, `frequency_heatmap_card.dart`, `rir_trend_card.dart`, `one_rm_leaderboard_card.dart`, `pr_timeline_card.dart`). All built from `fl_chart` + design tokens, mirroring `_ExerciseChartCard` structure.
7. **`presentation/` — wire into `stats_screen.dart`:** append `const AdvancedSection()` as the **last** child of the existing `ListView`, after `_ExerciseChartCard`. The free children above it are not reordered or modified.
8. **Settings toggle** for the opt-in volume-landmark band (decision 7) in the existing settings surface.

## 7. Acceptance criteria

- [ ] **No retroactive paywall (the critical check):** with `entitlementProvider == false`, the Stats screen renders the per-exercise **top-set**, **volume**, and **est-1RM** charts, the metric segmented control, the exercise selector, the 30-day delta pill, and the BEST footer **exactly as before this SOW** (verified by diffing the free path + a widget test asserting all three `StatsMetric` cards render when locked). No free chart is hidden, blurred, teased, or gated.
- [ ] A non-entitled user sees the Advanced section in its **locked** state (upsell card with `UNLOCK ADVANCED` → SOW-06 paywall), and **no advanced data** leaks through it.
- [ ] An entitled user sees all five advanced views (per-muscle volume, frequency heatmap, RIR-trend, 1RM leaderboard, PR timeline), each rendering real data from completed sessions, or the per-view "INSUFFICIENT DATA" state when sparse.
- [ ] Per-muscle volume buckets unmapped exercises under `'other'` and never crashes on `NULL muscle_group`.
- [ ] RIR-trend uses logged `rir` and is labeled descriptively ("lower = closer to failure"), with **no prescriptive/coaching language**.
- [ ] Est-1RM leaderboard and the free est-1RM chart report the **same** Epley value for the same data (single source of truth).
- [ ] DB migrates cleanly v6 → v7 on an existing install with no data loss; a fresh install creates v7 directly.
- [ ] Volume-landmark band is **off by default** and only appears when the opt-in setting is enabled.
- [ ] No new pub dependency added (`fl_chart` only); `flutter analyze` clean.

## 8. Testing

**Unit tests (in-memory sqflite via `sqflite_common_ffi`, mirroring `test/queries_test.dart` / `test/dao_test.dart` / `test/workout_progress_test.dart` — note `test/queries_test.dart` already opens a v6 in-memory DB; bump its `version`/seed to include `schemaV7Up`):**

- `test/analytics_dao_test.dart` (new):
  - **Migration:** open v6 in-memory, apply `schemaV7Up`, assert `muscle_group`/`primary_muscle` columns + index exist and existing rows survive.
  - **muscleVolumeByWeek:** seed sessions across exercises in two muscle groups + one unmapped; assert per-group weekly `SUM(weight*reps)` and that unmapped rolls into `'other'`.
  - **sessionFrequency:** seed completed sessions on specific days; assert per-day counts; assert abandoned/active sessions are excluded (`status = 'completed'` only).
  - **rirTrend:** seed sets with varying `rir` across sessions; assert `AVG(rir)` per session in chronological order; assert a downward trend is detected (closer to failure).
  - **estimated1RMLeaderboard:** seed multiple exercises; assert ranking by `MAX(w*(1+reps/30))` and that the value equals the free chart's Epley for the same set.
  - **prTimeline:** seed an ascending then descending sequence; assert only genuine new-max events appear, newest-first.
  - **empty/sparse:** zero/one session returns empty/insufficient, never throws.
- `test/free_stats_regression_test.dart` (new, the trust guard): assert `exerciseProgressionProvider`, `loggedExercisesProvider`, and `trendDelta` produce identical output before/after this SOW's changes (lock the free contract so a future edit can't silently move it behind the gate).

**Widget tests:**
- Stats screen with `entitlementProvider` overridden to `false`: all three free `StatsMetric` cards present **and** the Advanced section shows the locked upsell.
- Overridden to `true`: the segmented advanced strip + each advanced card render (with seeded data and with empty data).

**Manual matrix:** v6→v7 upgrade on a real device with existing history (no loss); locked vs unlocked toggle; light + dark + all five accents on each advanced card; insufficient-data state per view.

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Accidentally gating a currently-free chart (trust catastrophe) | Med | Free path is frozen + `free_stats_regression_test.dart` locks it; explicit acceptance criterion + the §3a table reviewed in PR. |
| Analytics maze creep (Jefit trap) | Med | Decisions 1+7 cap scope at five views + one opt-in band; "is this a coaching surface?" gate in review. |
| Muscle taxonomy is incomplete (user exercises unmapped) | High | `NULL` → `'other'` bucket is graceful; per-muscle view still ships; exercise-level muscle editing is an explicit follow-up, not a blocker. |
| RIR-trend reads as coaching, drifting toward SOW-07's lane | Low | Descriptive-only copy (decision 5, AC); no nudge/recommendation; analytics describe, SOW-07 prescribes. |
| SOW-06 not yet merged blocks shipping | Med | `entitlementProvider` stub returns `false`; the locked upsell renders; SOW-10 ships dark/gated and lights up when SOW-06 lands. |
| Heavy aggregation jank on large histories | Low | All queries are indexed SQL over completed sessions; cache via `FutureProvider`; cap windows (weeks: 16 frequency / 8 volume). |
| DB migration data-loss bug (undermines the whole trust pillar) | Low | v7 is additive `ALTER TABLE ... ADD COLUMN` (nullable) only — no table rewrite; covered by the migration unit test + manual upgrade matrix. |

## 10. Definition of done

- **Shippable bar:** an entitled user gets five focused, beautiful advanced views (per-muscle volume, frequency heatmap, RIR-trend, 1RM leaderboard, PR timeline) plus the opt-in volume-landmark band; a non-entitled user sees an honest upsell **and every free chart exactly as before**; DB at v7; all tests green; `flutter analyze` clean.
- **Positioning claim unlocked:** "Deep analytics that actually use your RIR — focused, not a spreadsheet" — the surpass-on-RIR-trend line in [00-competitive-analysis.md](../00-competitive-analysis.md), delivered without breaking the free-core / no-retroactive-paywall promise in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md).
- **Update [02-roadmap.md](../02-roadmap.md):** flip SOW-10 status from `⬜ Not started` to `🟦 In progress` / `✅ Shipped`; confirm in the same edit that the free charts row still reads as free (the Phase-1 "confirm they stay free when monetization lands" note).
