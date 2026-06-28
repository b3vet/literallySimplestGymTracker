# SOW-01 — Plate Calculator

> **Status:** 🟦 Built — phone side `flutter analyze` + 82 tests green; watch side ported + logic-verified via swiftc, **pending an Xcode build/device check** · **Phase:** 0 — Existential · **Tier:** Free
> **Owner:** berke · **Est. size:** M
> **Strategic rationale:** Closes the single *existential* day-1 credibility gap — every credible rival (Strong, StrongLifts, Boostcamp, Liftin') ships a plate calculator, and its absence shows up in rivals' negative reviews (RP, Juggernaut). See [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) ("nail trust, speed, and the plate calculator first") and [00-competitive-analysis.md](../00-competitive-analysis.md) ("Plate calculator — the one *existential* day-1 gap … **We don't have one.**").

Every SOW in this folder follows the [SOW-00 template](SOW-00-template.md) structure. This one is grounded in the real files cited throughout and respects the non-negotiables in [README.md](../README.md): free core forever, market speed not "the watch," and minimalism as a discipline.

---

## 1. Goal & Constraints

**What this delivers**
- A **per-side plate breakdown** for any target weight: given the target, the bar weight, and the user's available plate inventory, show "what to load on each side" (e.g. `20 + 10 + 2.5 per side`), surfaced **inline** in the set logger and **glanceable** on the active-workout screen and the watch.
- When the exact target isn't loadable from the inventory, show the **closest achievable** weight and its breakdown, clearly flagged.
- The bar weight and plate inventory are **remembered** (a one-time settings step, sensible defaults out of the box) and respect kg/lb plus the per-exercise weight step.

**Why now**
- It is the cheapest *existential* fix on the roadmap ([02-roadmap.md](../02-roadmap.md), Phase 0). Lifters do this math at the rack between every working set; an app open at the rack that *can't* do it reads as incomplete. The roadmap gate: "do not advance until logging speed + plate calculator are demonstrably best-in-class."

**Hard constraints**
- **Free forever.** Never gated, now or after monetization lands (SOW-06). It is core logging-adjacent utility.
- **Must NOT slow logging.** The set-log wheel flow (`set_log_sheet.dart`) is the speed claim; the breakdown is a passive *readout* that updates as the weight wheel moves — it adds zero taps to logging a set.
- **No new dependency.** Pure Dart math + existing design tokens + the existing SharedPreferences settings pattern.
- **Minimalism guardrail.** A glanceable one-line readout, not a configuration maze. The inventory editor is a single settings screen the user touches once; the readout itself has no controls.
- **Must work on the watch.** Surfaced on `CurrentExerciseView.swift` and inside `SetLoggerView.swift`. StrongLifts and Liftin' put it on the wrist — we match that.

**Non-goals (deliberately NOT in this SOW)**
- No warm-up ramp percentages — that is [SOW-04](SOW-04-warmup-calculator.md).
- No per-exercise bar override (e.g. trap-bar / safety-squat-bar with a different bar weight). One global default bar + an optional inline bar toggle covers the 95% case; per-exercise bars are a possible fast-follow, explicitly out of scope here.
- No "micro-plate" fractional-plate purchasing advice, collar weight modelling, or "you need to buy X plates" coaching.
- No barbell-vs-dumbbell auto-detection. The breakdown assumes a loaded barbell; the user reads it only when it's relevant.
- **No workout-data schema change** (confirmed — see §5).

## 2. Competitive context

| App | Has it? | How / where | Where they fall short |
|---|---|---|---|
| **Strong** | Yes | Tap weight → plate view | Behind the brand's general stall; basics increasingly Pro-gated |
| **StrongLifts** | Yes | Phone **and watch** | Strong feature; but the app revoked its lifetime (Jan 2026) — trust-poisoned |
| **Boostcamp** | Yes | In-logger | Shallow watch; we match on phone and beat on the wrist's integration |
| **Liftin'** | Yes | Phone **and watch**, Apple-only | RPE not RIR; tap-not-crown — same "twin" we out-execute on speed |
| **RP Hypertrophy** | **No** | — | "no plate calc" is a cited 2.8★ complaint |
| **Juggernaut AI** | **No** | — | "no plate calc, no timer" is a cited complaint |

- **Match** = a correct per-side breakdown for a target weight, respecting kg/lb. Table stakes; four credible rivals ship it.
- **Surpass** = *zero-friction*: it is **never a separate screen you navigate to**. It lives **inline under the weight wheel** as you dial the set, **glanceable on the active-workout card**, and **on the watch** — and it honors the per-exercise weight step and "closest achievable" honestly instead of silently rounding. No rival surfaces it in all three places with our inline-while-dialing immediacy.

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Where it lives | **Inline readout** under the weight wheel in `set_log_sheet.dart` + a compact line on the active-workout card (`active_workout_screen.dart`) + watch (`SetLoggerView`/`CurrentExerciseView`). No standalone "calculator" route. | Surpass-via-zero-friction; never a screen you navigate to. |
| 2 | Storage of config | **SharedPreferences**, via the `settings_repository.dart` pattern (`AppSettings` + `SettingsNotifier`). Two keys: bar weight (kg) + plate inventory (kg counts). | No workout-data schema change needed (§5). Mirrors existing settings (unit, step, rest). |
| 3 | Canonical units | Store bar weight + inventory **in kg** (DB/wire unit), exactly like every other weight in the app (`weight.dart`). Convert for display via `WeightConv`. | One source of truth; kg/lb display is a pure formatting concern. |
| 4 | Default bar weight | **20 kg** default; user-editable. (Shown as ~45 lb when unit = lb; we store 20.0 kg and *display* the converted value — we do **not** swap to a 20 lb bar.) | The Olympic bar is 20 kg / ~44 lb worldwide; storing kg keeps math unit-agnostic. |
| 5 | Default inventory | A sensible **full commercial-gym set** per side is assumed *available in unlimited quantity* in v1: kg = {25, 20, 15, 10, 5, 2.5, 1.25}; lb-flavored users still get the kg set (we display converted). Pairs are assumed plentiful. | Minimalism: most users never edit it. "Unlimited per denomination" avoids a count-management maze; constrained inventory is an opt-in advanced toggle (§4). |
| 6 | Inventory model | v1: a **set of available plate denominations** (kg), each effectively unlimited. Optional per-denomination **max-pairs cap** is supported by the algorithm and the data model but the editor ships the unlimited path first. | Greedy works cleanly with unlimited; the cap is the only thing that forces a non-greedy fallback, and we keep that path but don't front-load its UI. |
| 7 | Algorithm | **Greedy descending** per side with a **bounded closest-achievable search** when greedy can't hit the exact half-target. | Plate denominations are canonically "greedy-safe" (each ≥ 2× the next where it matters); the bounded search handles odd targets + capped inventory honestly. |
| 8 | "Closest achievable" | When the exact per-side load is unreachable, show the **nearest loadable total** (ties → round **down**, never suggest more than asked) with a `≈` marker and the delta (e.g. `≈ 97.5 kg · −2.5`). | Honest-by-design (trust pillar). Silently rounding the displayed target would be a lie at the rack. |
| 9 | Below-bar targets | If target ≤ bar weight, show **"BAR ONLY"** (or "EMPTY BAR" if target < bar). No negative plates. | Correctness + a glanceable, unambiguous string. |
| 10 | Watch transport | Forward bar weight + inventory in the existing **watch snapshot** (`pigeons/watch_bridge.dart` → `WatchSnapshot`), compute the breakdown **on-watch** in Swift (mirrors `WeightConv` already living in `WatchFormat.swift`). | The watch already gets `unit` + per-exercise `defaultWeightKg`/`weightStepKg`; adding two fields is cheap and keeps the wrist offline-correct. |
| 11 | Odd/asymmetric loads | Only **whole pairs** are placed (one plate per side). Leftover that can't be paired is reported via the closest-achievable path, not a half-plate. | A barbell loads symmetrically; never tell the user to put a lone plate on one side. |

## 4. Design & UX

### Surfaces

**A. Inline in the set logger (`set_log_sheet.dart`) — the primary surface.**
A single passive line directly **below the WEIGHT picker column** (and above `SAVE SET`), recomputed in the existing `onChanged` of the weight wheel. It is read-only; it has no tap target except an optional small "bar" affordance (see below).

```
┌──────────────────────────────────────────────┐
│ SET 02                          8-12 · 100 KG │   ← existing eyebrow row
│                                          ±2.5 │   ← existing step cycler
│   ┌────────┐  ┌──────────────┐  ┌────────┐    │
│   │  REPS  │  │   WEIGHT kg  │  │  RIR   │    │   ← existing pickers
│   │   10   │  │     100      │  │   1    │    │
│   └────────┘  └──────────────┘  └────────┘    │
│                                                │
│  ╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶  │
│  PER SIDE · BAR 20         20 + 15 + 5   ⚖    │   ← NEW plate line
│  ╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶╶  │
│                                                │
│  ┌──────────────────────────────────────────┐ │
│  │                SAVE SET                   │ │
│  └──────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

Closest-achievable state (target 98 kg, only 2.5s and bigger available):
```
  PER SIDE · BAR 20      ≈ 97.5  20 + 15 + 2.5   ⚖    (−2.5)
```

Bar-only state (target ≤ bar):
```
  PER SIDE · BAR 20                  BAR ONLY    ⚖
```

- **Eyebrow** `PER SIDE · BAR 20` uses `LsType.monoMeta` in `surface.text2`. The `BAR 20` segment is a tap target (the small `⚖` affordance) that opens a compact bar-weight chooser (a `CupertinoActionSheet` of common bars: 20 / 15 / 10 kg, or 45 / 35 / 15 lb shown as their kg equivalents). Changing it here writes the global default via `SettingsNotifier.setBarWeightKg` (so it's remembered) and instantly recomputes.
- **Breakdown** `20 + 15 + 5` uses `LsType.monoData` (tabular figures) in `accent.accent` for the plate numbers, with `+` separators in `surface.text2`. Largest-first.
- **Closest marker** `≈ 97.5` and the delta `(−2.5)` use `LsSignals.danger`-free, muted `surface.text2` with the `≈` glyph in `accent.accentHi` — it's information, not an error.
- Tokens: hairline separators use `surface.border`; vertical rhythm uses `LsSpace.s2`/`LsGap.sub`; the row sits inside the sheet's existing `LsSpace.sheet` horizontal padding. Corner treatment not needed (it's an inline line, not a card).

**B. Active-workout card (`active_workout_screen.dart`) — glanceable.**
A compact one-liner beneath the meta-pills row (SETS / REPS / kg), showing the breakdown for the **current planned/last-logged working weight** so the lifter can pre-load the bar *before* opening the log sheet:
```
   PER SIDE          20 + 10 + 2.5            ⚖ BAR 20
```
Same tokens as (A), rendered with `MetaPill`-adjacent styling so it reads as part of the existing meta block, not a new module. Recomputes when the current exercise / its default weight changes.

**C. Watch (`SetLoggerView.swift` weight page + `CurrentExerciseView.swift` lift block).**
- In `SetLoggerView`, under the WEIGHT picker (which already shows the `stepPill`), add a single auto-scaling line: `20+15+5` (no spaces on the wrist to save width), prefixed `⚖` glyph, in `LSColor.text2` with accent numerals. Recomputes from `weightDisplay[entry]` as the crown turns.
- In `CurrentExerciseView`'s `liftBlock`, a tiny `per side` line under the meta pills for the current default weight. Display-only.
- Closest-achievable on the wrist: append `≈` before the value and the delta in parentheses, `minimumScaleFactor` handles the extra width.

### Interaction flow
1. User opens the log sheet (or just looks at the active-workout card). The plate line is already populated from the current weight.
2. As the weight wheel turns, the line recomputes synchronously in the existing `onChanged` (`setState`) — no async, no DB, no jank.
3. If the user wants a different bar (incline smith, women's 15 kg bar for the day), they tap `⚖ BAR 20`, pick, and the line + the stored default update.
4. First-run: the inventory + bar default are seeded (decision #4/#5) so the feature works with zero setup. A `PLATES` section in `settings_screen.dart` lets the user edit the available denominations and the default bar.

### Settings surface (`settings_screen.dart`)
A new `_Section(title: 'PLATES')` after `UNIT`, matching the existing `_Section` + bordered `Material`/`InkWell` row pattern:
- **Default bar** row → opens a bar chooser (same one as the inline `⚖`).
- **Available plates** row → opens a sheet listing each denomination as a toggle chip (`SetChip`-style), in the user's display unit; toggling writes the inventory set. (Advanced: a long-press on a denomination reveals an optional max-pairs stepper — ships behind the unlimited default, decision #6.)

## 5. Data & schema changes

**No workout-data (sqflite) schema change.** Confirmed by reading `lib/core/db/migrations.dart` (DB is at v6) and `database.dart` (`_dbVersion = 6`): the plate calculator reads weights that already exist (`workout_sets.weight`, `program_exercises.default_weight`, the per-exercise `weight_step`) and needs no new table or column. **Do not bump the DB version for this SOW.**

**Settings additions only** (SharedPreferences, mirroring `settings_repository.dart`):

In `AppSettings` (add fields + `copyWith`):
```dart
final double barWeightKg;            // default 20.0
final List<double> plateInventoryKg; // available denominations (kg), each unlimited in v1
```
In `SettingsRepository`:
```dart
static const _kBarWeight   = 'settings.bar_weight_kg';
static const _kPlateInv    = 'settings.plate_inventory_kg';
static const double defaultBarWeightKg = 20.0;
static const List<double> defaultPlateInventoryKg =
    [25, 20, 15, 10, 5, 2.5, 1.25];

// read(): _prefs.getDouble(_kBarWeight) ?? defaultBarWeightKg;
//         (_prefs.getStringList(_kPlateInv)?.map(double.parse).toList())
//             ?? defaultPlateInventoryKg;
Future<void> writeBarWeightKg(double kg) async =>
    _prefs.setDouble(_kBarWeight, kg);
Future<void> writePlateInventoryKg(List<double> kg) async =>
    _prefs.setStringList(_kPlateInv, kg.map((p) => p.toString()).toList());
```
> Inventory is stored as a `StringList` of kg values because `SharedPreferences` has no `List<double>`. Parse on read, `toString()` on write — mirrors how the codebase already stringifies enums (`unit.name`, accent `name`).

In `SettingsNotifier`: add `setBarWeightKg(double)` and `setPlateInventoryKg(List<double>)`, each `await`-writing then `state = state.copyWith(...)` — identical shape to `setRestSeconds` / `setAccent`.

**Watch bridge / Pigeon contract change (decision #10):** add two fields to the `WatchSnapshot` class in `pigeons/watch_bridge.dart`:
```dart
double barWeightKg;          // global default bar
List<double> plateInventoryKg; // available denominations (kg)
```
Regenerate via the existing pigeon codegen (`watch_bridge.g.dart` / `WatchBridge.g.swift`). Populate them in the snapshot builder (`watch_snapshot.dart`) from `AppSettings`. The watch reads `unit` already; these two complete the on-watch compute. **No watch-side persistence** — the snapshot is the source of truth, recomputed each sync.

## 6. Implementation plan

Ordered by layer. The plate math is the only genuinely new logic; everything else is wiring into existing files.

**1. `domain/` — the pure plate-math (new file).**
`lib/features/workout/domain/plate_math.dart`
- `class PlateResult { final List<double> perSide; final double achievableTotalKg; final bool exact; final double bar; bool get barOnly; double get deltaKg; }`
- `PlateResult solvePlates({required double targetKg, required double barKg, required List<double> inventoryKg, Map<double,int>? maxPairs})` — see §7 pseudocode. Pure, no Flutter imports, fully unit-testable. **Build and test this first.**

**2. `application/` — a tiny formatter + providers.**
- `lib/features/workout/application/plate_format.dart` (or extend an existing util): `String formatPlateLine(PlateResult r, WeightUnit unit)` → `"20 + 15 + 5"`, `"BAR ONLY"`, `"≈ 97.5  20 + 15 + 2.5"`. Reuses `WeightConv.fromKg` for the per-plate display values and the achievable total.
- No new Riverpod provider strictly required — the inline readout reads `settingsProvider` (already watched in `set_log_sheet.dart`) for `barWeightKg`/`plateInventoryKg` and computes synchronously. (Optional: a small memoized `Provider.family` keyed by `(targetKg, barKg)` if profiling shows recompute cost — it won't at these sizes.)

**3. `core/settings/` — persistence (modify).**
- `settings_repository.dart`: add the two keys, defaults, read wiring, and two writers (§5).
- `settings_provider.dart`: add `setBarWeightKg` / `setPlateInventoryKg`.

**4. `presentation/` — phone UI.**
- `set_log_sheet.dart`: add a `_PlateLine` widget rendered below the picker `Row` and above `LsButton`. Recompute in the WEIGHT column's existing `onChanged` (it already calls `setState`). Add the `⚖ BAR n` tap → bar chooser action sheet → `setBarWeightKg`.
- `active_workout_screen.dart`: add a compact plate line under the meta-pills `Wrap` in `_exerciseView`, computed from `current.defaultWeightKg` (or last-logged) + settings.
- `settings_screen.dart`: add the `PLATES` `_Section` (default-bar row + available-plates editor sheet).
- (Optional shared) `lib/features/workout/presentation/plate_line.dart`: a single `PlateLine` stateless widget used by both the sheet and the card to avoid duplicating tokens.

**5. Watch bridge (modify) + watch (Swift).**
- `pigeons/watch_bridge.dart`: add `barWeightKg` + `plateInventoryKg` to `WatchSnapshot`; regenerate `watch_bridge.g.dart` + `ios/Runner/WatchBridge.g.swift`.
- `lib/features/workout/application/watch_snapshot.dart`: populate the two new fields from `AppSettings`.
- New `ios/LSWatch Watch App/PlateMath.swift`: a Swift mirror of `solvePlates` (≈40 lines), unit-mirroring the Dart algorithm exactly. Add a `PlateConv`-style formatter alongside `WeightConv` in `WatchFormat.swift`.
- `WatchWorkoutModel.swift`: expose `barWeightKg` + `plateInventory` from the decoded snapshot.
- `SetLoggerView.swift`: add the plate line under the WEIGHT picker, recomputed from `weightDisplay[entry]`.
- `CurrentExerciseView.swift`: add the `per side` line in `liftBlock`.

**6. Tests** (§8) — write the Dart `plate_math_test.dart` alongside step 1; add a Swift parity test if the watch target has a test bundle, otherwise a manual parity check (§8 matrix).

## 7. Acceptance criteria

- [ ] `solvePlates` returns the correct largest-first per-side list for an exact target (e.g. 100 kg, 20 kg bar, full kg inventory → `[20, 15, 5]` per side; 40 kg total each side).
- [ ] When the target is unreachable, `exact == false`, `achievableTotalKg` is the **nearest loadable total ≤** the unreachable value on a tie, and `deltaKg` is signed correctly.
- [ ] Target ≤ bar → `barOnly == true`, `perSide` empty; UI shows `BAR ONLY` (or `EMPTY BAR` if strictly below bar).
- [ ] Only whole pairs are ever returned (no lone single-side plate).
- [ ] Inline readout in `set_log_sheet.dart` updates **synchronously** as the weight wheel turns — no async gap, no DB read, no visible jank (verified by eye + a widget pump test).
- [ ] Logging a set requires **the same number of taps as before** (the plate line adds zero required interactions).
- [ ] kg/lb honored: switching unit re-displays plate values in the chosen unit (kg keeps half-precision, lb rounds whole, per `WeightConv`); stored config stays in kg.
- [ ] Per-exercise weight step honored: a target that lands on the exercise's step is treated as exact; the closest-achievable search snaps to loadable plate combinations, not to the wheel step.
- [ ] Bar weight + inventory **persist** across app restart (SharedPreferences) and default correctly on a fresh install (20 kg bar, full kg set).
- [ ] Changing the bar via the inline `⚖` writes the global default and recomputes immediately.
- [ ] Watch shows the same breakdown for the same inputs as the phone (parity), computed offline from the snapshot.
- [ ] No DB version bump; `_dbVersion` stays 6 and no migration is added.
- [ ] Feature is reachable with zero configuration on first run.

## 8. Testing

**Unit tests — plate math (the load-bearing logic).** New `test/plate_math_test.dart` (plain Dart test, no sqflite needed — mirrors the lightweight style of `test/workout_progress_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/workout/domain/plate_math.dart';

void main() {
  const full = [25.0, 20, 15, 10, 5, 2.5, 1.25];

  test('exact: 100kg / 20kg bar -> [20,15,5] per side', () {
    final r = solvePlates(targetKg: 100, barKg: 20, inventoryKg: full);
    expect(r.exact, isTrue);
    expect(r.perSide, [20.0, 15, 5]);           // 40 per side * 2 + 20 bar = 100
    expect(r.achievableTotalKg, 100);
  });

  test('exact: 60kg / 20kg bar -> [20] per side', () {
    final r = solvePlates(targetKg: 60, barKg: 20, inventoryKg: full);
    expect(r.perSide, [20.0]);
  });

  test('bar only: target == bar', () {
    final r = solvePlates(targetKg: 20, barKg: 20, inventoryKg: full);
    expect(r.barOnly, isTrue);
    expect(r.perSide, isEmpty);
  });

  test('below bar: target < bar -> bar only, exact false, negative delta', () {
    final r = solvePlates(targetKg: 15, barKg: 20, inventoryKg: full);
    expect(r.barOnly, isTrue);
    expect(r.exact, isFalse);
    expect(r.deltaKg, lessThan(0));             // can't go below the empty bar
  });

  test('closest: 98kg unreachable -> 97.5 (tie rounds down), delta -0.5', () {
    final r = solvePlates(targetKg: 98, barKg: 20, inventoryKg: full);
    expect(r.exact, isFalse);
    expect(r.achievableTotalKg, 97.5);          // 38.75 per side: 20+15+2.5+1.25
    expect(r.deltaKg, closeTo(-0.5, 1e-9));
  });

  test('only-paired: never returns a lone single-side plate', () {
    final r = solvePlates(targetKg: 22.5, barKg: 20, inventoryKg: [1.25]);
    // 2.5 total of plates needed = 1.25 per side -> exact [1.25]
    expect(r.perSide, [1.25]);
  });

  test('capped inventory forces non-greedy fallback', () {
    final r = solvePlates(
      targetKg: 100, barKg: 20, inventoryKg: [25, 20],
      maxPairs: {25.0: 1, 20.0: 1},             // only one pair of each
    );
    // best reachable per side = 25+20 = 45 -> 110 overshoots target? no:
    // greedy 25 then 20 = 45 per side = 110 > 100, so it must drop to
    // 25 only (90) or find the closest <= path -> assert closest, not crash.
    expect(r.exact, isFalse);
    expect(r.perSide, isNotEmpty);
  });

  test('lb-configured inventory still solves in kg space', () {
    // inventory stored in kg regardless of display unit
    final r = solvePlates(targetKg: 60, barKg: 20, inventoryKg: full);
    expect(r.perSide, [20.0]);
  });
}
```

**Formatter test.** `formatPlateLine` for exact / closest / bar-only across kg and lb (assert `"20 + 15 + 5"`, `"BAR ONLY"`, `"≈ 97.5  20 + 15 + 2.5"`, and the lb-rounded variants).

**Settings round-trip test.** Extend the settings coverage (in-memory `SharedPreferences.setMockInitialValues({})`): write a bar weight + a trimmed inventory, re-`read()`, assert the values survive and that a fresh prefs map yields the documented defaults.

**Widget test.** Pump `set_log_sheet.dart`, drive the weight wheel via the `FixedExtentScrollController`, and assert the plate line text updates synchronously and that no extra tap is needed to save (mirrors the harness in `test/widget_test.dart`).

**Watch parity (manual matrix).** No shared test bundle across Dart/Swift, so verify by hand on the same inputs:

| Case | target / bar / inventory | Expect (phone == watch) |
|---|---|---|
| Exact even | 100 / 20 / full kg | `20+15+5` |
| Exact small | 25 / 20 / full kg | `2.5` |
| Bar only | 20 / 20 / full kg | `BAR ONLY` |
| Below bar | 10 / 20 / full kg | `EMPTY BAR` (delta < 0) |
| Closest | 98 / 20 / full kg | `≈ 97.5  20+15+2.5+1.25` |
| lb display | 135 lb / 45 lb-bar(=20kg) / full | values shown lb-rounded, same plates |
| Unit flip mid-set | toggle kg↔lb while sheet open | line re-displays without reopening |

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Greedy gives a non-minimal/odd breakdown for a weird inventory | Low | Standard plate denominations are greedy-safe; the bounded closest-achievable search (§7) covers gaps and capped inventories. Unit tests pin the known-tricky cases (98 kg, capped 25/20). |
| lb users confused by a "20 kg" bar default | Medium | Display the bar in their unit (≈45 lb) while storing 20 kg; the bar chooser lists familiar bars. We never silently swap to a 20 lb bar. |
| Inline line nudges logging speed / adds visual noise | Medium | It's a passive single line with no required interaction; the recompute is O(plates) synchronous math. Acceptance criteria explicitly gate on "same tap count" + "no jank." If it ever feels heavy, it degrades to the active-workout card only. |
| Watch/phone drift (two implementations of the algorithm) | Medium | Keep `PlateMath.swift` a line-for-line mirror of `plate_math.dart`; the manual parity matrix (§8) is a required pre-merge check; both read identical snapshot inputs so divergence can only come from the algorithm, which the matrix catches. |
| Pigeon regen churn touches generated files already dirty in the tree | Low | The watch bridge `.g` files are already modified on this branch (WIP); regenerate cleanly from `pigeons/watch_bridge.dart` and diff-review only the two added fields. |
| Scope creep into per-exercise bars / micro-plate advice | Medium | Explicitly listed as non-goals (§1). One global bar + inline override is the locked v1 surface. |

## 10. Definition of done

- **Shippable bar:** `solvePlates` is correct and fully unit-tested; the inline readout is live in the set logger and on the active-workout card; the watch shows the matching breakdown offline; bar + inventory persist and default sanely; logging speed is unchanged; no DB version bump.
- **Positioning claim unlocked:** the existential day-1 gap is closed — LS now matches every credible rival on the plate calculator and **surpasses** them by surfacing it inline-while-dialing, on the card, and on the wrist. This is a prerequisite for the [02-roadmap.md](../02-roadmap.md) Phase 0 gate ("do not advance until logging speed + plate calculator are demonstrably best-in-class").
- **Roadmap update:** flip [SOW-01 in 02-roadmap.md](../02-roadmap.md) from `⬜ Not started` to `✅ Shipped`, and confirm in the Phase 0 section that the gate's plate-calculator condition is met.

---

## 11. Implementation notes (build — 2026-06-23)

**What shipped vs the spec.** Built as specced (inline readout in the set logger + active-workout card + watch; kg-canonical storage; SharedPreferences config; no DB bump — `_dbVersion` stays 6). Files: new `lib/features/workout/domain/plate_math.dart`, `application/plate_format.dart`, `presentation/plate_line.dart`; settings (`settings_repository.dart` / `settings_provider.dart` — `barWeightKg` + `plateInventoryKg`); UI (`set_log_sheet.dart`, `active_workout_screen.dart`, `settings_screen.dart`); watch (`pigeons/watch_bridge.dart` + regen, `watch_snapshot.dart`, `WCSessionManager.swift`, `WatchWorkoutModel.swift`, new `PlateMath.swift`, `SetLoggerView.swift`, `CurrentExerciseView.swift`).

**Deviations / corrections from the spec (all verified):**
- **Algorithm: bounded min-plates DP, not greedy.** Adversarial review proved plain greedy-descending misses exact solutions on non-canonical inventories reachable via the plate editor (e.g. `{25,20,15} @ 90 kg` → greedy returns `[25]`=70 kg "−20", but `20+15`=90 kg exact exists) — a direct violation of decision #8's honesty pillar. Replaced with a min-plate subset-sum DP (centi-kg integer grid; respects pair caps; exact when reachable, else true nearest-below). Mirrored line-for-line in `PlateMath.swift` (logic compiled + verified with swiftc).
- **Two SOW-draft test expectations were wrong and were corrected:** 100 kg → `[25,15]` (greedy-minimal, fewer plates), not `[20,15,5]`; below-bar delta is **positive** (loading the empty bar over-shoots a below-bar target), not negative. `deltaKg` is a consistent signed `achievable − target`.
- **Signed delta added** to the closest-achievable readout (phone + watch), e.g. `≈ 97.5  25 + 10 + 2.5 + 1.25 (−0.5)` (was missing vs §4 mock).
- **Empty-inventory floor:** the plate editor now keeps ≥ 1 denomination selected (an empty inventory would misleadingly read "BAR ONLY").
- **lb ≈-total consistency:** the approximate total is derived from the displayed (rounded) plates so it always equals their sum in lb.
- **lb plates** still display the kg set converted (decision #5) — a true lb plate set (45/35/25/10/5/2.5 + 45 lb bar) remains a fast-follow.

**Tests:** `plate_math_test.dart` (17, incl. the non-canonical regression cases), `plate_format_test.dart` (11, incl. lb-consistency + delta), `settings_plate_roundtrip_test.dart` (2). Full suite 82 green; `flutter analyze` clean. **Not added:** a `set_log_sheet` widget-pump test (the synchronous-recompute path is structurally guaranteed — it runs in `build()` — and was verified by inspection; a pump test is a low-priority follow-up).

**⚠ Before flipping to ✅ Shipped — manual Xcode verification (watch cannot compile here):**
1. Build BOTH targets (Runner + LSWatch Watch App). Confirm new `PlateMath.swift` is in the **watch** target's Compile Sources (it should auto-join via the synchronized group — it must NOT join Runner, which has its own formatter).
2. Phone↔watch parity on a real/paired device: same breakdown for the same inputs.
3. Plate line fits 40/41 mm (incl. the longer `≈ … (−x)` and lb cases) via `.minimumScaleFactor`.
4. Live recompute as the Crown turns; bar chooser + plate editor persist.

**Out-of-scope artifact:** an agent created `docs/PRIVACY_POLICY.md` during the watch work (accurate, but not part of this SOW) — left untracked for you to keep or remove.
