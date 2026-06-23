# SOW-04 — Warm-up Set Calculator

> **Status:** ⬜ Not started · **Phase:** 1 · **Tier:** Free
> **Owner:** berke · **Est. size:** S
> **Strategic rationale:** Closes the third "places we may be back" gap — a warm-up ramp is cheap, expected, and shipped by Strong and Liftin' while we have nothing but a motivational tip (`lib/features/tips/data/tips_content.dart:31`). It is a recommendation-stopper to clear, not a differentiator to win. See [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) (Phase 1 = "clear every recommendation-stopper") and [00-competitive-analysis.md](../00-competitive-analysis.md) gap #3.

This SOW follows [SOW-00-template.md](SOW-00-template.md). It is grounded in real files (cited `lib/...` paths), matches the Riverpod tri-layer + `shared_preferences`-settings architecture, and respects the non-negotiables in [README.md](../README.md) (free core forever; minimalism is a discipline).

---

## 1. Goal & Constraints

- **What this delivers**
  - Before the working sets of an exercise, an **optional, glanceable warm-up ramp card** that suggests 2-4 lighter sets (e.g. 50 / 70 / 85% of today's working weight, plus the working set itself as the ramp's endpoint), each **rounded to a weight the lifter can actually load** on the bar.
  - **One-tap to log a ramp step as a normal set** if the lifter wants it counted (it lands as an ordinary `workout_set` row — never a special "warm-up" type), or ignore the card entirely.
  - A single **"Warm-up ramp" setting** to pick the percentage scheme (or turn it off), with a sensible default.
- **Why now** — Phase 1 table-stakes. Strong and Liftin' ship a warm-up calculator; its absence is a cheap, visible gap that shows up in feature comparisons. Low complexity, high "of course it has that" payoff.
- **Hard constraints**
  - **Free.** Never gated (non-negotiable #1).
  - **Minimalism (non-negotiable #4).** A small card that a lifter who doesn't want it never has to touch — **zero added taps for users who skip it.** It renders inline above the set rows and is collapsible/dismissable; it is **never a modal, never forced, never blocking** the LOG SET CTA.
  - **No new dependency.** Pure-Dart math + existing design-system widgets only.
  - Must respect the user's unit (kg/lb), the per-exercise `weightStepKg`, and dark/light theme.
- **Non-goals (deliberately NOT in this SOW)**
  - **No warm-up persistence.** No `set_type` column, no `is_warmup` flag, no warm-up table — see Locked Decision #1. A logged warm-up is just a normal set.
  - **No true plate decomposition** (e.g. "load 20 + 10 + 2.5 per side"). That is **SOW-01 (plate calculator)**, which does not exist yet. This SOW rounds to the loadable *increment* (the weight step), and is written so it can delegate to SOW-01's plate math the moment that ships — see Locked Decision #4.
  - **No warm-up on the watch** in Phase 1 (the watch's screen real-estate and crown flow are tuned for working sets; a ramp card there is out of scope). Revisit after the phone card proves out.
  - No per-set rest-timer behaviour change, no auto-logging of the whole ramp, no bar-only/empty-bar special-casing beyond the scheme's lowest step.

## 2. Competitive context

| Rival | Has warm-up calc? | How | Where it falls short |
|---|---|---|---|
| **Strong** | Yes | Percentage-of-working-weight ramp, auto-inserted warm-up sets | Warm-ups are persisted as a distinct set *type* and counted into the set list — clutter for lifters who just want a hint; basics are Pro-gated. |
| **Liftin'** | Yes | Warm-up ramp suggestion | Tap-driven (no crown); no rounding-to-loadable surfacing as a headline. |
| **Hevy / Jefit** | Partial / via templates | Warm-up sets as a set type you mark manually | Manual, not calculated; adds taps. |
| **RP / Juggernaut** | No | — | Notably absent; shows up in their negative reviews alongside "no plate calc, no timer". |

- **Match:** suggest a percentage ramp off today's working weight, shown before the working sets.
- **Surpass (our angle):**
  1. **Round every ramp step to a weight the lifter can actually load** (reuse the per-exercise weight step today; delegate to the SOW-01 plate calculator when it ships) — most rivals show raw `0.5×working` math that lands on un-loadable numbers.
  2. **Ephemeral by default.** Unlike Strong, we do **not** pollute the set list or the database with warm-up rows. It's a guide; logging one is opt-in and lands as a normal set. This keeps the minimalism promise *and* the data model clean.
  3. **Zero added taps for the skipper.** The card collapses to a one-line summary and never blocks the primary CTA.

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | **Warm-up persistence** | **NONE. No DB column, no table, no set type.** Warm-ups are UI-only / ephemeral. If a user logs one, it is written as an ordinary `workout_set` row (reps/weight/rir/set_group/group_seq) indistinguishable from a working set. | Architectural decision restated from the brief. `WorkoutSet` (`lib/features/workout/domain/workout_set.dart`) has no type column and we are not adding one. Keeps the schema (DB v6) untouched, keeps stats/PR/export honest (a warm-up *is* a set the lifter did), and keeps the betrayal surface zero. The ramp is computed on the fly from today's working weight. |
| 2 | **Source of "today's working weight"** | `PlannedExercise.defaultWeightKg` for the current exercise (the same value the LOG SET sheet seeds and the meta-pill shows). | It is already the single source of truth for the planned top weight (`active_session.dart`, used in `active_workout_screen.dart:243` meta pill and `set_log_sheet.dart:113`). No new state. |
| 3 | **Default ramp scheme** | **`50 / 70 / 85%`** of working weight (3 warm-up steps), working set shown as the `100%` endpoint. Default ON. | A widely-taught, low-complexity ramp; matches the roadmap's example "50/70/85/100%" ([02-roadmap.md](../02-roadmap.md) line 47). Three steps is enough guidance without becoming a workout of its own. |
| 4 | **Rounding to loadable weight** | Round each ramp step to the **effective weight step** for the exercise: `weightStepKg ?? unit.defaultStep`, computed in **kg** (the storage unit), then display via `WeightConv.format`. Expose the rounding as a single pure function `WarmupRamp.roundToLoadable(kg, stepKg)` so **SOW-01's true plate decomposition can replace the body without touching call sites**. | Reuses `ProgramExercise.weightStepKg` / `PlannedExercise.weightStepKg` (`lib/features/programs/domain/program_exercise.dart:26`, `active_session.dart:31`) and `WeightUnit.defaultStep` (`settings_repository.dart:15`). SOW-01 (plate calculator) does **not** exist yet, so we cannot import its math today; the function boundary is the forward seam. |
| 5 | **Scheme storage** | A `shared_preferences` setting on `SettingsRepository` (`warmupScheme`: an enum / off), **not** a DB row. | Mirrors every other preference (unit, weightStep, restSeconds, accent) in `lib/core/settings/settings_repository.dart`. No migration. |
| 6 | **Interaction model** | Inline collapsible card above the set rows; **never modal, never blocks the CTA.** Tapping a ramp step opens the existing `showSetLogSheet` pre-filled with that step's reps/weight so logging it is the same one flow as a normal set. | Reuses `set_log_sheet.dart` verbatim — no new logging path, no new validation, no new haptics to maintain. |
| 7 | **Warm-up reps** | Suggested reps are a fixed, light, descending hint per step (e.g. `10 / 5 / 3`), shown as guidance only and fully editable in the log sheet. NOT derived from the program's `targetReps`. | Warm-up reps are by convention low and unscored; the lifter edits freely. Keeps the math trivial and the card glanceable. |

## 4. Design & UX

**Where it lives:** inside `_exerciseView` in `lib/features/workout/presentation/active_workout_screen.dart`, in the scrolling content column, placed **between the set-chips row (line ~274) and the set-log rows (line ~283)** — i.e. above the working-set list, where a warm-up logically precedes the work. It is built from a small new widget `WarmupRampCard` and consumes the new `warmupRampProvider`.

**Design-system mapping:**
- Card container: `LsCard` (`lib/core/widgets/layout.dart:384`) or a bordered `Container` with `BorderRadius.circular(LsRadius.r3)`, matching the existing `_SetRow` / `_PreviousSetsBanner` treatment.
- Eyebrow: `EyebrowLabel('WARM-UP')` (`brand.dart:58`).
- Step numbers/weights: `LsType.monoData` / `LsType.monoMeta`, accent via `t.accent.accent`, dim text via `t.surface.text2/3` — identical to `_SetRow`.
- Spacing: `LsGap.sub` / `LsGap.section`; collapse chevron uses `LsIconSquare` or a plain `Icon`.
- Dismiss/collapse persists per-session only (ephemeral `setState`), not to disk — see risks.

**ASCII mock (expanded — default state):**

```
┌──────────────────────────────────────────┐
│ WARM-UP                              ⌄    │   ← EyebrowLabel + collapse chevron
│                                           │
│  W1   40 kg  × 10        50%      [ LOG ]  │   ← rounded to step; tap row or LOG → set sheet
│  W2   55 kg  ×  5        70%      [ LOG ]  │
│  W3   65 kg  ×  3        85%      [ LOG ]  │
│  ─────────────────────────────────────    │
│  WORK  80 kg            100%               │   ← endpoint, not loggable here (use LOG SET)
└──────────────────────────────────────────┘
  (working weight today: 80 kg · scheme 50/70/85)
```

**ASCII mock (collapsed — the skipper's default after one tap, zero further friction):**

```
┌──────────────────────────────────────────┐
│ WARM-UP · 40 → 55 → 65 kg            ⌃    │   ← one glanceable line, no taps required to ignore
└──────────────────────────────────────────┘
```

**Flow:**
1. Card renders automatically when the scheme is ON and the exercise has a working weight > the lowest loadable increment. If the scheme is OFF, **the card does not render at all** (true zero-tap skip).
2. Tap a ramp row (or its `LOG` affordance) → `showSetLogSheet(context, exercise: current, setNumber: …, initialReps: <hint>, initialWeightKg: <rounded step>)`. The user confirms/edits and it logs through the **existing** `activeSessionProvider.notifier.logSet(...)` path (`active_workout_screen.dart:448`) — a normal set, identical to any other.
3. Logging a warm-up does **not** advance the working-set count specially; it's just another logged set against this exercise (consistent with how `setsLoggedForCurrent` already counts everything for the exercise — see note in Risks about set-chip counting).
4. The card is collapsible; collapse state is per-session UI only.

**Settings UI:** add a "Warm-up ramp" row to the existing settings screen (wherever unit / rest / weight-step rows live — `lib/features/settings/...`), a segmented/cycler control: `Off · 50/70/85 · 60/80 · 40/60/80`. Default `50/70/85`.

**Watch:** out of scope (Non-goals). No watch-bridge / Pigeon changes.

## 5. Data & schema changes

**No schema change.** No new table, no new column, no migration, no `database.dart` version bump. This is the central locked decision (#1): warm-ups are never persisted as a distinct concept.

**Settings (the `settings_repository.dart` pattern — `shared_preferences`, NOT the DB):**
- Add a `WarmupScheme` enum (in `settings_repository.dart` alongside `WeightUnit`):
  - `off`, `r50_70_85` (default), `r60_80`, `r40_60_80`.
  - Each non-off value carries its percentage list and a matching reps-hint list, e.g.
    `r50_70_85 → percents [0.50, 0.70, 0.85], reps [10, 5, 3]`.
- `AppSettings`: add `final WarmupScheme warmupScheme;` (+ `copyWith`).
- `SettingsRepository`: add `_kWarmupScheme = 'settings.warmup_scheme'`, read in `read()` with default `r50_70_85`, and `writeWarmupScheme(WarmupScheme)`.
- `SettingsNotifier` (`settings_provider.dart`): add `setWarmupScheme(WarmupScheme)`.

**Watch bridge / Pigeon:** none.

## 6. Implementation plan

Ordered by layer. New files marked **(new)**.

1. **`domain` / pure util — `lib/core/util/warmup_ramp.dart`** **(new)**
   - `enum WarmupScheme` lives in `settings_repository.dart` (so settings can reference it without a cycle); the *math* lives here.
   - `class WarmupRamp`:
     - `static double roundToLoadable(double kg, double stepKg)` — `(kg / stepKg).round() * stepKg`, clamped ≥ `stepKg`. **The SOW-01 seam.**
     - `static List<WarmupStep> build({required double workingKg, required double stepKg, required List<double> percents, required List<int> repHints})` — maps each percent → `roundToLoadable(workingKg * pct, stepKg)`, pairs with rep hint, **drops duplicate/degenerate steps** (two percents that round to the same weight, or any step ≥ working weight after rounding).
   - `class WarmupStep { final double weightKg; final int reps; final double percent; }`.
   - Mirrors `WeightConv` in `lib/core/util/weight.dart` — pure, no I/O, trivially unit-testable.

2. **`core/settings` — `lib/core/settings/settings_repository.dart`** (modify)
   - Add `WarmupScheme` enum (with `percents` / `repHints` getters and `off`).
   - Add field + persistence as in §5.
   - **`lib/core/settings/settings_provider.dart`** (modify): add `setWarmupScheme`.

3. **`application` — `lib/features/workout/application/warmup_provider.dart`** **(new)**
   - A small derived provider (`warmupRampProvider` / a `Provider.family` or a method) that takes the current `PlannedExercise` + watches `settingsProvider`, resolves `stepKg = exercise.weightStepKg ?? WeightUnit.kg.defaultStep`, and returns `WarmupRamp.build(...)` (or `const []` when scheme is `off`). No DB access — pure derivation, so it stays cheap and rebuild-safe.

4. **`presentation` — `lib/features/workout/presentation/warmup_ramp_card.dart`** **(new)**
   - `WarmupRampCard` (ConsumerWidget): reads `warmupRampProvider` for `current`; renders the card per the mock; per-row `onTap` calls a passed `onLogStep(WarmupStep)` callback. Collapse state via internal `StatefulWidget`/`setState`.

5. **`presentation` — `lib/features/workout/presentation/active_workout_screen.dart`** (modify)
   - In `_exerciseView`, insert `WarmupRampCard(exercise: current, onLogStep: _logWarmupStep)` between the set-chips row and the set-log rows (≈ line 278).
   - Add `_logWarmupStep(PlannedExercise current, WarmupStep step)`: calls the **existing** `showSetLogSheet(...)` pre-filled with `step.reps` / `step.weightKg`, then the **existing** `activeSessionProvider.notifier.logSet(...)` (same body as `_openSetLogSheet`, lines 431-455) — and starts the rest timer the same way. No new logging code path.

6. **`presentation` — settings screen** (`lib/features/settings/...`, modify)
   - Add the "Warm-up ramp" cycler row wired to `settingsProvider.notifier.setWarmupScheme`.

7. **Tip cleanup (optional, 1 line)** — `lib/features/tips/data/tips_content.dart:31` still nudges "don't skip warm-ups"; leave as-is or soften now that the feature exists (low priority, not a blocker).

## 7. Acceptance criteria

- [ ] With the default scheme, an exercise whose working weight is `80 kg` (step `2.5 kg`) shows three warm-up steps rounded to loadable weights (`40 / 55 / 65 kg` ≈ 50/70/85%, each snapped to the 2.5 kg step).
- [ ] Each ramp step's weight is a multiple of the exercise's effective step (`weightStepKg ?? unit.defaultStep`) — never an un-loadable fraction.
- [ ] Steps that round to the **same** weight, or to ≥ the working weight, are **dropped** (no duplicate or pointless rows).
- [ ] Tapping a ramp step opens the existing set-log sheet pre-filled with that step's weight + rep hint; confirming logs a **normal** `workout_set` (verified: the row has no special flag and is counted by existing stats/summary/export exactly like any set).
- [ ] **No DB migration, no schema change, no `database.dart` version bump** is introduced by this SOW (grep-verifiable).
- [ ] A lifter who never touches the card incurs **zero extra taps**; with the scheme set to **Off**, the card does not render at all.
- [ ] The scheme setting persists across app restarts (`shared_preferences`), defaults to `50/70/85`, and offers an Off option.
- [ ] Weights display correctly in both kg and lb (rounding is computed in kg, formatted via `WeightConv.format`), and respect dark/light theme.
- [ ] The card never blocks or overlaps the primary `LOG SET` / `NEXT EXERCISE →` CTA.

## 8. Testing

**Unit tests — ramp math (the load-bearing logic). New file `test/warmup_ramp_test.dart`,** plain `flutter_test` (no sqflite needed — the math is pure, unlike `dao_test.dart` / `queries_test.dart` which use `sqflite_ffi`):

- `roundToLoadable`: `roundToLoadable(80*0.5, 2.5) == 40.0`; `roundToLoadable(80*0.7, 2.5) == 55.0` (56 → 55); `roundToLoadable(80*0.85, 2.5) == 67.5` then assert dedup vs working; sub-step inputs clamp up to `stepKg`.
- `build` default scheme: `workingKg: 80, stepKg: 2.5, percents: [.5,.7,.85]` → three steps with expected rounded weights + rep hints `[10,5,3]`.
- **Dedup/degenerate:** a tiny working weight (e.g. `12.5 kg`, step `2.5`) where two percents collapse to the same step → assert duplicates removed; any step ≥ working dropped.
- **Step variants:** `stepKg: 0.5` (kg default) and an `lb`-derived step produce loadable multiples.
- **Off scheme** → `build` is not called / provider returns `const []` (covered at provider level).

**Widget tests (light):**
- `WarmupRampCard` renders N rows for the active scheme and **nothing** when scheme is `off`.
- Collapsed state shows the one-line summary and no `LOG` affordances.
- Tapping a row invokes `onLogStep` with the correct `WarmupStep`.

**Manual matrix:**
- kg and lb units; an exercise with a custom `weightStepKg` (e.g. 1.25) vs none; very light working weight (single warm-up or none); collapse/expand; confirm a logged warm-up appears in the summary as a normal set and in CSV export (SOW-02) with no special marker; verify zero added taps when ignored.
- Regression: confirm the warm-up card does not shift the set-chip "done" count semantics in a confusing way (see Risks).

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Set-chip / "done" count confusion** — a logged warm-up is a normal set, so it counts toward `setsLoggedForCurrent` (`active_workout_screen.dart:137`) and the working-set chips, surprising a lifter who logged a warm-up "for the record." | Med | Default UX treats the ramp as a **guide** (log is opt-in). Document clearly in-card ("LOG counts it as a normal set"). Optionally, in a fast-follow, exclude warm-up-tagged-in-UI sets from the *chip* target — but since there is no persistence, the simplest honest answer is: a set you did is a set you did. Decide before build whether the card needs a one-line caption. |
| Rounding lands a warm-up *above* the working weight on tiny weights / coarse steps | Med | `build` drops any step that rounds ≥ working weight and any duplicate; covered by unit tests. |
| Minimalism creep — the card grows into a "warm-up workout" surface | Low | Hard cap at the scheme's 2-4 steps; no rest timer per warm-up, no auto-log-all, no watch port. Locked in Non-goals. |
| SOW-01 plate calculator changes the rounding contract later | Med | `roundToLoadable` is the single seam; SOW-01 replaces its body (true plate decomposition) without touching the provider, card, or tests' call shape. |
| Lifters who want warm-ups *persisted/typed* (Strong-style) feel it's "missing" | Low | Intentional per Locked Decision #1; the trade is a clean data model + honest stats. If demand is real, revisit as a separate SOW — do not add a column reflexively. |

## 10. Definition of done

- **Shippable bar:** the warm-up ramp card renders above the working sets for the current exercise, rounds every step to a loadable weight, logs through the existing set-log flow as a normal set, is fully skippable with zero added taps, and is configurable (incl. Off) via a persisted setting — all free, no schema change, ramp math green under unit tests.
- **Positioning claim unlocked:** removes [00-competitive-analysis.md](../00-competitive-analysis.md) "places we may be back" gap #3 ("Warm-up set calculator — we don't have one"); a Phase-1 recommendation-stopper cleared so r/weightroom can recommend us without that asterisk.
- **Roadmap update:** flip [02-roadmap.md](../02-roadmap.md) SOW-04 status from `⬜ Not started` → `✅ Shipped`, and note the forward dependency satisfied for SOW-01 (the `roundToLoadable` seam).
