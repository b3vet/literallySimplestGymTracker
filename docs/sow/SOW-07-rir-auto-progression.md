# SOW-07 — RIR-derived Auto-Progression

> **Status:** ⬜ Not started · **Phase:** 2 · **Tier:** Paid
> **Owner:** berke · **Est. size:** L
> **Strategic rationale:** The paid wedge — the one feature no rival occupies. Match Alpha Progression's loved RIR auto-progression engine and *surpass* it by delivering the nudge on the Apple Watch crown at log time, which Alpha (no watch) structurally cannot. Races the competitive clock in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) (§"The competitive clock ⏰") and fills the empty quadrant named in [00-competitive-analysis.md](../00-competitive-analysis.md) ("Nobody is fast + minimalist + RIR-native + watch-first").

This SOW follows the structure in [SOW-00-template.md](SOW-00-template.md). It is grounded in real files (`lib/...`, `ios/...`) and respects the minimalism guardrail and the trust pillar in [README.md](../README.md) / [01-strategy-and-positioning.md](../01-strategy-and-positioning.md).

> **Dependency:** This feature is gated behind the entitlement delivered by [SOW-06-monetization-foundation.md](SOW-06-monetization-foundation.md). SOW-06 is sequenced first in [02-roadmap.md](../02-roadmap.md) (Phase 2) precisely so there is an entitlement to gate this against. Where SOW-06 is not yet written, this SOW assumes its contract is a single boolean provider `proEntitlementProvider` (see §3 / §5) and lists the exact seam in §6.

---

## 1. Goal & Constraints

**What this delivers (user-visible):**
- When a lifter has demonstrably gotten *stronger at a constant load* — their logged RIR drifts up at the same working weight across recent sessions — LS surfaces **one** rationale-bearing nudge at the moment they open the set logger: e.g. *"80 kg at RIR 1 → now RIR 3. You've gotten stronger — add 2.5 kg?"* with **Add 2.5 kg** / **Keep 80 kg**.
- Accepting prefills the new (rounded-to-loadable) weight into the picker. Ignoring logs exactly what they would have logged anyway. The set is **always** skippable; nothing is auto-applied.
- The same nudge is delivered on the **Apple Watch** via the Digital Crown logger — the structural differentiator.

**Why now (the competitive/trust reason):**
- Alpha Progression has the best RIR auto-progression and a watch on its roadmap but *nothing shipped* (changelog through v6.1). Estimated lead **~12 months at ~60% confidence**; an Alpha watch inside 6 months collapses the watch-layer advantage. Phase 2 is the race ([01-strategy-and-positioning.md](../01-strategy-and-positioning.md) §"The competitive clock"). RIR is **already logged** per set on phone and watch (`WorkoutSet.rir`, crown RIR page in `ios/LSWatch Watch App/SetLoggerView.swift`). The input exists; what is missing is the **progression intelligence**.

**Hard constraints:**
- **Minimalism guardrail (critical, non-negotiable):** a SINGLE invited nudge at log time. Never a coaching surface, never a chat, never a feed, never an auto-applied change, never a multi-week mesocycle plan. The user accepts (prefill) or ignores. This is the named "minimalism trap" risk in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) (§Risks #4) — the layer that "could become the bloat we critique."
- **Honest framing:** the nudge is *effort-tracking* ("you've gotten stronger"), NOT a results promise ("gain X kg in Y weeks"). Trust pillar — no overclaiming.
- **Must work on the watch.** The nudge on the wrist is the whole point; a phone-only version forfeits the differentiator.
- **No new runtime dependency.** Engine is pure Dart; the watch reads a flattened field already on the snapshot wire.
- **Weight is stored kg; rounding honors per-exercise `weightStepKg`** via `WeightConv` (`lib/core/util/weight.dart`) — never suggest an unloadable weight.
- **Paid:** gated behind the SOW-06 entitlement. Free users never see the nudge (but RIR logging itself stays free and skippable — see §"free/paid boundary").

**Non-goals (deliberately NOT built):**
- ❌ Alpha's full **4-week-ramp + deload mesocycle** structure. That is the bloat we reject by name.
- ❌ Rep-target progression, double-progression schemes, percentage-of-1RM auto-programming, or RPE↔RIR conversion (we are RIR-native, no RPE field exists).
- ❌ A "progression history / coaching" screen, a streak meter, or any notification outside the set logger.
- ❌ Auto-editing the program template's `default_weight`. The nudge prefills *this set only*; the user may separately edit their program. (A future opt-in "apply to program" is explicitly out of scope here.)
- ❌ Down-regulation / fatigue suggestions ("you got weaker, drop weight"). That is the HRV-readiness lane ([SOW-09](SOW-09-hrv-readiness.md)), not this one. This engine only ever suggests *adding* load.

## 2. Competitive context

| App | Has RIR? | Acts on it? | Watch? | Where it falls short |
|---|---|---|---|---|
| **Alpha Progression** | Yes (loved, 4.9★) | Yes — best-in-class auto-progression | **No** | No Apple Watch — the only reason our wedge is open. Couples progression to a full mesocycle (ramp + deload) the minimalist segment finds heavy. |
| **Hevy** | RPE logged | **No** — decorative; "logged but not acted on" | Wear OS | RIR/RPE is a stored number with no engine behind it. |
| **Boostcamp** | Free RIR | No engine | Shallow watch | Free RIR undercuts the *input*, not the *intelligence*. |
| **RP Hypertrophy** | Yes (0–4, most credentialed) | Yes | **No** | No offline, no timer, no plate calc, no watch (2.8★). The science without the gym-floor UX. |
| **Dr. Muscle** | Yes (DUP) | Yes | Has a watch | Dated 2016 UI, single-method, top-of-category price; auto-regulation is a black box, not an *invited* nudge. |

**What "match" looks like:** an RIR-drift engine that detects the same "you're ready to add weight" signal Alpha's users love, with a clear rationale.

**What "surpass" looks like:** that nudge appears **on the wrist, at log time, driven by the crown** — the exact intersection ([00-competitive-analysis.md](../00-competitive-analysis.md): "RIR + watch = empty quadrant, ours for ~12 months") — and stays a *single invited nudge*, not a coaching regime. We win on **placement** (the watch) and on **restraint** (one nudge, honest framing), not on algorithmic sophistication. Decision-trigger to watch ([02-roadmap.md](../02-roadmap.md)): *Alpha ships an Apple Watch app → accelerate this SOW hard.*

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | The signal | **RIR drift up at constant load** across recent sessions for the same exercise | Matches the research-committed rule and Alpha's loved mechanic. RIR is the effort proxy we already log; same-load drift is the cleanest "got stronger" signal. |
| 2 | Trigger threshold | **Mean RIR rose by `> 2.0`** at the same working weight, comparing the most recent eligible session vs. the baseline of prior eligible sessions (≥ 2 sessions of evidence total) | The committed rule. `> 2` (strictly greater) keeps it conservative — a 1-point RIR wobble (estimation noise) never fires. |
| 3 | Load increase | **+2.5% to +5%** of the working weight, rounded to the loadable step | Standard small-jump auto-regulation. Magnitude scales with drift (see §6 algorithm): bigger drift → top of the range. |
| 4 | Rounding | Round the raw target to the nearest multiple of the exercise's **`weightStepKg`** (fallback: unit default), via `WeightConv`. **Never round below current weight** (guarantee a real increase, ≥ one step). | Honor per-exercise loadability (`program_exercises.weight_step`, `WorkoutSet`/`WeightConv` in `lib/core/util/weight.dart`). A rounded-down suggestion = no suggestion. |
| 5 | Activation gate | **≥ 10 completed sessions logged OR self-identified intermediate+**, AND the exercise itself has ≥ 2 eligible same-load sessions | RIR estimation is unreliable for beginners and high-rep sets. Gating is an *accuracy* decision, not a paywall (paywall is decision #9). |
| 6 | High-rep exclusion | **Exclude sets with reps > 15** from the engine entirely | RIR estimation degrades badly at high reps (research-committed). A 20-rep set's "RIR 3" is noise. |
| 7 | Suggestion cardinality | **At most ONE nudge per logger open**, for the *current working set's* exercise, computed from history *before* this set | Minimalism guardrail. Never a list, never stacked, never mid-set re-prompts. |
| 8 | Acceptance model | Accept = prefill the new weight into the picker (still fully editable; user can dial it back). Ignore = the picker keeps its normal prefill. **Decision is never persisted as a program change.** | One invited nudge; no auto-apply; honest history. |
| 9 | Free/paid boundary | The **engine + nudge are PAID** (SOW-06 entitlement). **RIR logging, charts, 1RM, prefill-from-last stay FREE and unchanged.** | The basic/smart seam from [01-strategy-and-positioning.md](../01-strategy-and-positioning.md): never gate core logging; gate the *intelligence*. |
| 10 | Where it computes | **Phone computes** the suggestion (it owns the DB + entitlement). The watch *receives* a per-exercise suggestion field on the existing snapshot and renders it — it never recomputes. | The watch has no DB and no entitlement check; the snapshot is already the phone's authoritative projection (`watch_snapshot.dart`). Keeps one engine, one source of truth. |
| 11 | "Deload" / reset detection | If the working weight *dropped* since the last session for this exercise, **do not fire** (treat as an intentional reset, not progress) | Avoids nudging up right after a planned back-off. |
| 12 | Cooldown after accept | After a suggestion is shown for an exercise at a given weight, **do not re-fire for the same weight** until the lifter has logged ≥ 1 session at the *new* weight | Stops the same nudge re-appearing every set / every session before the new load has any history. |

## 4. Design & UX

### 4.1 Phone — inside the set log sheet (`set_log_sheet.dart`)

The nudge is a **dismissible banner above the pickers** inside the existing `LsSheet` — not a new screen, not a dialog. It appears only when the engine returns a suggestion for this exercise *and* the user is entitled. It maps to the design system: `EyebrowLabel`, `LsType.monoMeta`, `LsAccentSpec` accent for the affordance, `LsGap` spacing, `LsRadius.r3` rounding — identical primitives to the rest of the sheet.

```
┌──────────────────────────────────────────────┐
│  SET 3                              8-12 · 80 KG │
│                                                │
│  ┌────────────────────────────────────────┐  │   ← nudge banner (accent-bordered, r3)
│  │ ↑ STRONGER                              │  │
│  │ 80 kg felt RIR 1 → now RIR 3.           │  │   ← rationale, honest framing
│  │ You've gotten stronger.                 │  │
│  │                                         │  │
│  │   [ ADD 2.5 KG ]      Keep 80 kg        │  │   ← accept (filled) / ignore (text)
│  └────────────────────────────────────────┘  │
│                                                │
│        ±2.5 KG                                  │
│   REPS      WEIGHT        RIR                   │
│    10       80  →  82.5    1                    │   ← Accept jumps WEIGHT wheel to 82.5
│   ───      ──────────     ──                    │
│                                                │
│  [             SAVE SET             ]          │
└──────────────────────────────────────────────┘
```

Interaction:
- **Accept** (`ADD 2.5 KG`): `_weightDisplay` jumps to the rounded target; the WEIGHT `FixedExtentScrollController` animates to that item; banner collapses; `HapticFeedback.selectionClick()`. The user can still dial it anywhere — accepting is a prefill, not a commit.
- **Ignore** (`Keep 80 kg`, plain text button): banner collapses; picker untouched; no state persisted.
- Banner is shown **once per logger open** (decision #7). Re-opening the sheet for the next set recomputes; the cooldown (decision #12) prevents nagging at the new weight.
- If not entitled or no suggestion: the sheet is byte-for-byte the current sheet (zero layout shift). The banner widget returns `SizedBox.shrink()`.

### 4.2 Watch — inside the crown logger (`SetLoggerView.swift`)

The watch shows the nudge as a **first compact page** in the existing `TabView` pager *only when* the snapshot carries a suggestion for the current exercise — then the normal REPS → WEIGHT → RIR pages follow. The crown still drives everything; this adds one swipe-away page, never a modal.

```
   ┌─────────────────┐        ┌─────────────────┐
   │ ↑ STRONGER       │        │ SET 3 · WEIGHT  │
   │                 │   →    │      kg         │
   │ 80→RIR 3        │ swipe   │   ┌─────────┐   │
   │ Add 2.5 kg?     │        │   │  82.5   │   │   ← if accepted, weight page
   │                 │        │   └─────────┘   │      starts on the suggested value
   │  ◉ ADD   ○ KEEP │        │   ±2.5 kg       │
   └─────────────────┘        └─────────────────┘
     crown / tap                crown scroll
```

Interaction:
- The suggestion page is `pages[0]` only when `model.currentExercise?.suggestion != nil`. **ADD** sets `weightDisplay[0]` to the suggested (snapped) value and advances to the WEIGHT page; **KEEP** advances with the normal prefill. `WKInterfaceDevice.current().play(.click)` on choice.
- No suggestion → the pager is exactly today's REPS/WEIGHT/RIR (no extra page). The watch never computes; it only renders `WatchExercise.suggestion` (§5).
- Drop-set exercises: suggestion applies to the **top** entry's weight only (drops remain −20% of the accepted top).

### 4.3 Settings (one toggle)

A single switch in Settings: **"Strength nudges"** (on by default for entitled users). Persists via the `settings_repository.dart` pattern (decision below). Off → engine never runs, banner/page never appears. Honors the "always skippable / always controllable" trust stance.

## 5. Data & schema changes

**No `workout_sets` / `program_exercises` schema change.** RIR, weight, reps, and `weight_step` already exist (DB v6). The engine reads existing columns. The DB version in `lib/core/db/database.dart` stays at **6**.

**Settings flag (SharedPreferences, not SQLite):** add `strengthNudgesEnabled` to `AppSettings` in `lib/core/settings/settings_repository.dart`, mirroring `liveActivityEnabled` exactly:
- key `settings.strength_nudges`, default `true`, `read()` + `writeStrengthNudgesEnabled(bool)`, threaded through `copyWith` and `settings_provider.dart`.

**Entitlement provider (from SOW-06):** this SOW consumes `proEntitlementProvider` (a `Provider<bool>` or `FutureProvider<bool>`). If SOW-06 names it differently, adapt the single read site in `progression_provider.dart`. No entitlement code is *defined* here — only *consumed*.

**Pigeon / watch bridge contract change (additive):** add an optional `suggestion` field to `WatchExercise` so the phone can hand the watch a precomputed nudge. Edit `pigeons/watch_bridge.dart`, then regenerate (`dart run pigeon --input pigeons/watch_bridge.dart`) → updates `lib/features/workout/application/watch_bridge.g.dart` (Dart) and `ios/Runner/WatchBridge.g.swift` (Swift). The watch side (plain Swift, decodes the JSON) gains a matching optional struct.

```dart
// New Pigeon class in pigeons/watch_bridge.dart
class WatchProgressionSuggestion {
  WatchProgressionSuggestion({
    required this.fromWeightKg,     // the constant load the drift was measured at
    required this.suggestedWeightKg,// rounded, loadable, strictly > fromWeightKg
    required this.baselineRir,      // mean RIR at the baseline session(s)
    required this.currentRir,       // mean RIR at the most recent eligible session
  });
  double fromWeightKg;
  double suggestedWeightKg;
  int baselineRir;
  int currentRir;
}

// Add to WatchExercise:
WatchProgressionSuggestion? suggestion; // null => no nudge for this slot
```

Bump `watchSnapshotSchemaVersion` in `lib/features/workout/application/watch_snapshot.dart` from **3 → 4** (the watch "ignores unknown newer versions" — older watch builds simply don't render the page). `buildWatchSnapshot` populates `suggestion` per queue slot **only when the user is entitled and the toggle is on** (it receives a `Map<String, ProgressionSuggestion?> suggestionsByExerciseId` computed by the controller, mirroring how it already receives `settings`).

## 6. Implementation plan

Ordered by layer, naming the specific files.

### 6.1 `domain/` — the pure engine (no DB, no Flutter)
**New file `lib/features/workout/domain/progression_engine.dart`.**

```
// ── Inputs (plain values, fully unit-testable) ──────────────────────────────
class ExerciseRirSample {                  // one logged working set, projected
  final double weightKg;
  final int reps;
  final int rir;
  final DateTime sessionStartedAt;         // groups samples into sessions
}

class ProgressionConfig {
  static const double driftThreshold   = 2.0;   // decision #2: strictly >
  static const int    maxRepsForRir    = 15;    // decision #6
  static const int    minSessionsTotal = 2;     // decision #2: ≥2 sessions of evidence
  static const double minIncreasePct   = 0.025; // decision #3
  static const double maxIncreasePct   = 0.05;
}

class ProgressionSuggestion {
  final double fromWeightKg;
  final double suggestedWeightKg;
  final int    baselineRir;     // rounded mean for display
  final int    currentRir;      // rounded mean for display
}

// ── The engine: pure, deterministic, no side effects ────────────────────────
ProgressionSuggestion? suggestProgression({
  required List<ExerciseRirSample> history,   // all working sets for ONE exercise,
                                              // any order; engine sorts + groups
  required double currentWeightKg,            // the load the lifter is about to use
                                              // (prefill = last logged / target)
  required double? weightStepKg,              // null => unit default passed by caller
  required double unitDefaultStepKg,
}) {
  // 1. FILTER: drop high-rep noise (reps > maxRepsForRir → excluded). decision #6
  final usable = history.where((s) => s.reps <= ProgressionConfig.maxRepsForRir);

  // 2. GROUP into sessions by sessionStartedAt; within each session keep only
  //    sets at the working weight == currentWeightKg (constant-load comparison).
  //    "==" uses a tolerance of half the step so 80.0 == 80.0 across float noise.
  final sessions = groupBySession(usable)
      .map((sets) => sets.where((s) => sameLoad(s.weightKg, currentWeightKg, step)))
      .where((sets) => sets.isNotEmpty)
      .toList();                              // chronological, oldest → newest

  // 3. GATE — evidence: need ≥ minSessionsTotal eligible same-load sessions.
  if (sessions.length < ProgressionConfig.minSessionsTotal) return null; // #2

  // 4. DELOAD/RESET guard: if the most recent NON-eligible (any-weight) session's
  //    top weight for this exercise was BELOW currentWeightKg, the lifter just
  //    came back up from a back-off — not steady progress. Do not fire. decision #11
  if (cameUpFromLowerLoad(history, currentWeightKg)) return null;

  // 5. COMPUTE drift: meanRir(mostRecentSession) - meanRir(baseline), where
  //    baseline = mean RIR across ALL earlier eligible sessions (so a single
  //    fluky session can't anchor the baseline).
  final current  = meanRir(sessions.last);
  final baseline = meanRir(flatten(sessions.sublist(0, sessions.length - 1)));
  final drift    = current - baseline;

  // 6. THRESHOLD: strictly greater than driftThreshold (a 2.0 wobble never fires).
  if (drift <= ProgressionConfig.driftThreshold) return null;             // #2

  // 7. MAGNITUDE: scale % with drift — drift just over 2 → +2.5%, drift ≥ ~4 → +5%.
  final pct = lerpClamped(drift, from: 2.0, to: 4.0,
                          lo: ProgressionConfig.minIncreasePct,
                          hi: ProgressionConfig.maxIncreasePct);
  final rawTarget = currentWeightKg * (1 + pct);

  // 8. ROUND to a loadable weight; guarantee a real increase of ≥ one step. #4
  final step    = (weightStepKg ?? unitDefaultStepKg);
  var   snapped = (rawTarget / step).round() * step;
  if (snapped <= currentWeightKg) snapped = currentWeightKg + step;       // never round down

  return ProgressionSuggestion(
    fromWeightKg: currentWeightKg,
    suggestedWeightKg: snapped,
    baselineRir: baseline.round(),
    currentRir:  current.round(),
  );
}
```

The **activation gate** (decision #5: ≥10 sessions OR intermediate+) lives **one layer up** in the provider, NOT in the pure engine — the engine is a pure "does this history justify a bump?" function so it can be unit-tested with tiny fixtures; the provider decides whether to even *call* it. Edge cases handled inside the engine: new exercise (empty/short history → step 3 returns null), missed sessions (no calendar assumption — sessions are ordered by `sessionStartedAt`, gaps are irrelevant), deload (step 4), high-rep (step 1), float-noise load equality (step 2 tolerance), rounding-down (step 8).

### 6.2 `data/` — the query (one new DAO method)
**Edit `lib/features/workout/data/workout_dao.dart`.** Add:

```dart
/// All working sets for an exercise from COMPLETED sessions, projected for the
/// progression engine: weight, reps, rir, and the owning session's started_at
/// (to group samples into sessions). Ordered oldest → newest. Mirrors the
/// existing JOIN shape in stats_provider's exerciseProgressionProvider.
Future<List<ExerciseRirSample>> rirHistoryForExercise(String exerciseId) async {
  final rows = await _db.rawQuery('''
    SELECT s.started_at, ws.weight, ws.reps, ws.rir
    FROM workout_sets ws
    JOIN workout_sessions s ON s.id = ws.session_id
    WHERE ws.exercise_id = ? AND s.status = 'completed'
    ORDER BY s.started_at ASC, ws.logged_at ASC
  ''', [exerciseId]);
  return rows.map(/* → ExerciseRirSample */).toList();
}

/// Count of completed sessions (for the ≥10-sessions activation gate, decision #5).
Future<int> completedSessionCount() async {
  final r = await _db.rawQuery(
    "SELECT COUNT(*) AS c FROM workout_sessions WHERE status = 'completed'");
  return (r.first['c'] as num).toInt();
}
```

These reuse the exact JOIN + `status = 'completed'` filter already in `stats_provider.dart` and the index `idx_sets_exercise_time`. No new query against an unindexed path.

### 6.3 `application/` — the provider + wiring
**New file `lib/features/workout/application/progression_provider.dart`:**
- `FutureProvider.family<ProgressionSuggestion?, ProgressionRequest>` where `ProgressionRequest = (exerciseId, currentWeightKg, weightStepKg)`.
- Body: **gate first** — `if (!ref.watch(proEntitlementProvider)) return null;` then `if (!ref.watch(settingsProvider).strengthNudgesEnabled) return null;` then the activation gate: read `completedSessionCount()`; if `< 10` **and** not self-identified intermediate+ → `return null`. Only then fetch `rirHistoryForExercise` and call the pure `suggestProgression(...)` with the unit-default step from settings.
- Self-identified level: a single onboarding/settings value (reuse `settings_repository.dart`; out of this SOW to *design* the onboarding question — if SOW-06/onboarding hasn't added it, the gate falls back to the ≥10-sessions count alone, which is the safe conservative default).

**Edit `lib/features/workout/application/active_workout_controller.dart`:** when building the snapshot for the watch, compute a `Map<String, ProgressionSuggestion?>` for the queue's exercises (entitled + toggle on only) and pass it into `buildWatchSnapshot`. No change to `logSet` — the suggestion is advisory; whatever weight is logged is logged. Invalidate the family after `logSet`/`finish` so the next open recomputes (the cooldown, decision #12, falls out naturally: once a set lands at the new weight, the old-weight comparison no longer has a fresh "current" session above threshold).

**Edit `lib/features/workout/application/watch_snapshot.dart`:** `buildWatchSnapshot` takes `Map<String, ProgressionSuggestion?> suggestionsByExerciseId`; populate `WatchExercise.suggestion`; bump `watchSnapshotSchemaVersion` 3 → 4.

### 6.4 `presentation/` — phone UI
**Edit `lib/features/workout/presentation/set_log_sheet.dart`:** `showSetLogSheet` already receives `exercise` + `initialWeightKg`. In `_SetLogSheetState.build`, `ref.watch` the `progressionSuggestionProvider((exerciseId, _weightDisplay-in-kg, stepKg))`; render a new private `_ProgressionNudge` widget above the picker `Row` when non-null. Accept → `setState` `_weightDisplay`, `_weightCtrl.animateToItem(...)`, collapse. Ignore → collapse. Guard so the nudge computes against the **prefill** weight (the constant load), recomputing if the user manually changes the wheel is *not* required (decision #7: one nudge per open).

### 6.5 watch (Swift)
- **`pigeons/watch_bridge.dart`** (+ regenerate): `WatchProgressionSuggestion`, `WatchExercise.suggestion`.
- **`ios/LSWatch Watch App/WatchWorkoutModel.swift`**: decode `suggestion` into the watch's `WatchExerciseVM` (a `suggestion: WatchSuggestionVM?`).
- **`ios/LSWatch Watch App/SetLoggerView.swift`**: prepend the suggestion `PageSpec` to `pages` when `model.currentExercise?.suggestion != nil`; ADD sets `weightDisplay[0]`; KEEP is a no-op advance. Mirror `CurrentExerciseView.swift`'s accent + type primitives. New small view `SuggestionPage` (eyebrow "↑ STRONGER", two crown-tappable choices).
- **`ios/Runner/WCSessionManager.swift`** / `WatchBridge.g.swift`: regenerated — no hand edits beyond what Pigeon emits.

## 7. Acceptance criteria

- [ ] **Engine, happy path:** 80 kg logged at mean RIR 1 in an earlier session and mean RIR 3 in the latest (both ≤ 15 reps, ≥ 2 sessions) → `suggestProgression` returns a suggestion with `suggestedWeightKg` rounded up to a multiple of `weightStepKg`, strictly `> 80`.
- [ ] **Threshold is strict:** drift of exactly +2.0 RIR → **no** suggestion. Drift of +2.5 → suggestion.
- [ ] **High-rep exclusion:** identical drift but all sets at 20 reps → no suggestion (samples filtered out).
- [ ] **Evidence gate:** only one same-load session in history → no suggestion.
- [ ] **Deload guard:** weight dropped vs. the prior session → no suggestion (decision #11).
- [ ] **Rounding never goes down:** raw target rounds below current → engine returns `current + step`.
- [ ] **Step honored:** `weightStepKg = 1.25` and `= 5.0` produce loadable multiples; `null` step falls back to the unit default passed by the caller.
- [ ] **Activation gate:** a user with `< 10` completed sessions and not intermediate+ → provider returns null even when the engine *would* fire.
- [ ] **Free/paid boundary:** with `proEntitlementProvider == false`, the provider returns null; the set sheet renders identically to today (no banner, no layout shift). RIR wheel + charts + 1RM unchanged.
- [ ] **Skippable:** Ignore logs exactly the prefill weight; Accept prefills but the weight remains fully editable before SAVE.
- [ ] **One nudge:** at most one banner per logger open; no stacking, no re-prompt mid-sheet.
- [ ] **Watch parity:** with a suggestion present, the crown logger shows the suggestion page first; ADD starts the WEIGHT page on the suggested value; with no suggestion the pager is unchanged (REPS/WEIGHT/RIR).
- [ ] **Snapshot version:** older watch builds (schema 3) ignore the new field and behave exactly as before; `watchSnapshotSchemaVersion == 4`.
- [ ] **Honest framing:** copy says effort/strength ("you've gotten stronger"), never a results/time promise.

## 8. Testing

**Unit (the engine — the load-bearing tests).** New `test/progression_engine_test.dart`, in-memory-free (the engine is pure — no sqflite needed), mirroring the fixture style of `test/workout_progress_test.dart` (`_set`, `_session` helpers). Deterministic cases:

| Case | History (same exercise) | `currentWeightKg` | Expect |
|---|---|---|---|
| Canonical add | S1: 80×8 RIR 1; S2: 80×8 RIR 3 | 80, step 2.5 | suggest **82.5**, from 80, baseline 1, current 3 |
| Just-under threshold | S1: 80 RIR 1; S2: 80 RIR 3 (drift 2.0) | 80 | **null** |
| Over threshold by 0.5 | S1: 80 RIR 0.5; S2: 80 RIR 3 | 80 | suggest |
| Drift scales % | S1: 80 RIR 0; S2: 80 RIR 4 (drift 4) | 80, step 2.5 | suggest **≈ +5% → 84 → snapped 85** |
| High-rep noise | both sessions 80×20 RIR 1→3 | 80 | **null** (filtered) |
| One session only | S1: 80 RIR 1 | 80 | **null** |
| Mixed loads | S1: 70 RIR 3; S2: 80 RIR 1; S3: 80 RIR 3 | 80 | suggest (only 80-kg sessions compared) |
| Deload reset | S1: 80 RIR 3; S2 (most recent, lower): 70 | 70 | **null** (came up from below) |
| Round-down guard | drift fires, step 5, raw target 82 | 80 | **85** (never 80) |
| Step = null | canonical, step null, unitDefault 0.5 | 80 | snapped to 0.5 multiple |
| Float-noise equality | 80.0 vs 79.9999 | 80 | treated as same load |

**Unit (DAO).** Extend `test/dao_test.dart` / `test/queries_test.dart` (in-memory sqflite via `sqflite_ffi`): `rirHistoryForExercise` returns only completed-session working sets, ordered, with the right `started_at`; `completedSessionCount` excludes active/abandoned.

**Provider/gate.** Riverpod `ProviderContainer` overriding `proEntitlementProvider` and `settingsProvider`: assert null when un-entitled, null when toggle off, null under the activation gate, suggestion when all gates pass.

**Widget.** `set_log_sheet` golden/pump: banner present iff provider non-null; Accept moves the wheel; Ignore is a no-op; zero layout shift when null.

**Manual matrix (watch + reliability — the differentiator):**
- Phone logs → suggestion appears on the watch logger after the next snapshot push; ADD on the crown prefills; KEEP does not.
- Older watch build (schema 3) paired with new phone (schema 4): no crash, no nudge, normal logging.
- Toggle off mid-session → nudge disappears on both surfaces on the next snapshot.
- Un-entitle (restore/refund simulation): nudge gone, logging untouched, no data loss (trust pillar).

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **False positives** (nudge to add weight when the lifter wasn't really stronger — RIR was mis-estimated) | Med | Strict `> 2` drift, ≥ 2 same-load sessions, baseline = mean of *all* prior eligible sessions (one fluke can't anchor), high-rep exclusion, deload guard. Suggestion is always skippable — worst case the user taps "Keep". |
| **Beginner inaccuracy** (RIR unreliable < intermediate) | High | Activation gate (decision #5): ≥10 sessions OR intermediate+. Default-conservative when the level question is absent (sessions count alone). |
| **Becoming the bloat we critique** (the named minimalism-trap risk) | High | Hard cap: ONE invited nudge at log time, no surface, no chat, no auto-apply, no mesocycle. Decisions #7/#8 are non-negotiable; any PR that adds a second nudge surface or a coaching screen violates this SOW. |
| **Over-promising → trust damage** | Med | Copy is effort-framed ("you've gotten stronger"), never a results/timeline promise. Reviewed against the trust pillar in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md). |
| **Unloadable suggestion** (e.g. 81.3 kg on a 2.5-kg-plate gym) | Med | Always rounds to `weightStepKg` (decision #4); never below current. |
| **Nag fatigue** (same nudge every set/session) | Med | One per logger open (#7) + cooldown until a session lands at the new weight (#12). |
| **Watch/phone schema skew** | Low | Additive Pigeon field + version bump 3→4; old watch ignores unknown newer versions (existing contract). |
| **Entitlement coupling to unshipped SOW-06** | Med | Single read site (`proEntitlementProvider`); if SOW-06 names it differently, one-line change. Engine + tests are entitlement-agnostic. |
| **Alpha ships a watch first** | Low–Med (the clock) | This SOW *is* the race. Monitor Alpha's changelog ([02-roadmap.md](../02-roadmap.md) trigger); the watch nudge is the defensible half. |

## 10. Definition of done

**Shippable bar:**
- Pure engine implemented + the full deterministic unit suite green (§8 table).
- DAO queries + provider gate (entitlement → toggle → activation gate) wired and tested.
- Phone nudge banner in the set sheet: accept prefills, ignore is a no-op, zero layout shift when absent, honest copy.
- Watch crown logger renders the suggestion page from the snapshot; ADD/KEEP behave; schema bumped 3→4; old-watch compatibility verified.
- Free users (and un-entitled/toggle-off) see no nudge and an unchanged logging path; RIR/charts/1RM remain free.

**Positioning claim it unlocks:** *"RIR on your wrist — and the moment you've gotten stronger, your watch tells you to add weight. One twist of the crown to accept."* The empty-quadrant wedge from [00-competitive-analysis.md](../00-competitive-analysis.md), shipped where Alpha cannot follow until it ships a watch.

**Update on ship:**
- [02-roadmap.md](../02-roadmap.md): flip SOW-07 status ⬜ → ✅ Shipped; note the watch-RIR-nudge differentiator is live and re-confirm the Alpha-watch decision-trigger is being monitored.
- [01-strategy-and-positioning.md](../01-strategy-and-positioning.md): the "one bet" (RIR auto-progression on the wrist) is now in-market; update the moat note ("the moat is rented") with the realized-vs-pending status.
