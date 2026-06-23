# SOW-08 — Supersets

> **Status:** ⬜ Not started · **Phase:** 2 · **Tier:** Free
> **Owner:** berke · **Est. size:** M
> **Strategic rationale:** Closes the "Strong/Hevy/Jefit all do supersets, we don't" recommendation gap with a feature lifters explicitly ask for, while staying minimalist — and surfaces the `set_group` primitive that DB v6 was explicitly built to "future-proof supersets." See [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) (match-and-surpass, minimalism-by-discipline) and [00-competitive-analysis.md](../00-competitive-analysis.md) (per-rival cheat sheet).

This SOW follows [SOW-00-template.md](SOW-00-template.md). It is grounded in real files (`lib/...` paths cited throughout), matches the existing Riverpod tri-layer + sqflite cumulative-migration architecture, and respects the non-negotiables in [README.md](../README.md).

---

## 1. Goal & Constraints

**What this delivers** (user-visible):
- In the **day editor**, a user can group 2+ consecutive exercises into a **superset** (rendered `A1 / A2 / …`) and ungroup them.
- During a **workout**, a superset is logged as **alternating rounds**: log A1 set 1 → A2 set 1 → (rest) → A1 set 2 → A2 set 2 → (rest) … The cursor walks the round; **rest fires after the last member of each round**, not after every member.
- Supersets work on the **watch** — the bridge already carries the grouping fields needed; the watch logs and advances within a round the same way the phone does.

**Why now:** Supersets are table-stakes for the "fast logger" camp (Strong, Hevy) and the "program/library" camp (Jefit) per [00-competitive-analysis.md](../00-competitive-analysis.md). They're a frequently-requested, low-surface-area feature that fits "minimalist by discipline" — and DB v6 already left the door open: `lib/core/db/migrations.dart` (`schemaV6Up`) and `lib/features/workout/domain/workout_set.dart` both call out the `set_group`/`group_seq` primitive as "supersets later." Phase 2 is the moat phase; this is a cheap free win that rounds out the program model alongside the paid wedge.

**Hard constraints:**
- **Free tier** — no entitlement gate (per [01-strategy-and-positioning.md](../01-strategy-and-positioning.md): never gate core logging).
- **Must work on the watch** — the crown wedge is the product. The Pigeon bridge (`pigeons/watch_bridge.dart`, schema v3) and the watch model (`ios/LSWatch Watch App/WatchWorkoutModel.swift`) must carry and honor the grouping.
- **No new dependency** — `uuid`, `sqflite`, Riverpod only.
- **Reuse the existing primitive where it fits.** The runtime `set_group` (`workout_sets.set_group`/`group_seq`) is a **per-set-instance** group and stays exactly as-is for drop sets. Supersets are a **template/queue-level** grouping (multiple *exercises*), which is a different axis — see §3 Decision 1.
- **Preserve drop-set behavior** — a superset member may *itself* be a drop-set exercise; the two groupings are orthogonal and must compose.
- **Cursor correctness** — the cursor must walk superset rounds in order and **resume correctly** after an app relaunch / watch-resync (the `cursorAfter` invariant in `active_workout_controller.dart`).

**Non-goals (explicitly NOT this SOW):**
- ❌ A **circuit / EMOM / AMRAP builder.** Supersets are strictly "alternating A1/A2/… rounds with smart rest." No time-based rounds, no round-count picker beyond per-member `targetSets`, no rest-between-members config.
- ❌ **Cross-day or reorderable-across-the-group** supersets — members are **contiguous** in the day. Grouping is "select adjacent rows."
- ❌ **Mid-workout creation of a superset** from two already-separate queue slots. Supersets are defined in the program template (Phase 2). Session-scoped *editing* of a superset (skip a member, swap a member) reuses the existing override machinery; forming a *new* group at runtime is deferred.
- ❌ Unequal round handling beyond the natural one (a member with fewer `targetSets` simply drops out of later rounds — see §4).

## 2. Competitive context

| Rival | Supersets? | How | Where they fall short |
|---|---|---|---|
| **Strong** | Yes | Tag exercises into a superset; alternating logging | Core/Pro seam paywalls basics; Watch sync data-loss bug ([00](../00-competitive-analysis.md)) |
| **Hevy** | Yes | Superset grouping in builder + logger | "Overbuilt over time"; RIR decorative |
| **Jefit** | Yes | Superset/circuit support | Cluttered, 286MB, crashes — the bloat we avoid |
| **Setgraph** | No | — | "No program structure" — our minimalist twin lacks it |
| **Alpha Progression** | Limited | Program-side | **No Apple Watch** — can't deliver superset logging on the wrist |

**Match:** alternating-round logging with the right rest behavior, defined in the program — parity with Strong/Hevy on the gym floor.

**Surpass:**
1. **On the wrist.** No RIR-or-watch rival delivers superset round-logging via the Digital Crown. Alpha (best RIR) has no watch at all.
2. **Minimalist surface.** Group = "select adjacent rows + tag." No circuit builder, no nested config. One concept (`A1/A2 rounds`), reusing the queue/cursor we already have.
3. **Reliability claim intact.** Append-only set log + phone-as-source-of-truth ([01](../01-strategy-and-positioning.md)) is unchanged — supersets add a *template* grouping and a *cursor-walk* rule, not a new sync path.

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | **Where does superset grouping live — runtime `set_group` or a new program-level column?** | **New program-level grouping: `program_exercises.superset_group` (nullable TEXT id) + `superset_seq` (INT).** The runtime `workout_sets.set_group` is **NOT** reused for supersets. | `set_group` is a *per-logged-set-instance* "back-to-back unit" used to make a drop set's top+drops count as ONE completed set (`completedSetsFor`, `groupKey` in `active_session.dart`/`workout_set.dart`). A superset groups *multiple exercises across multiple rounds*, where each member's set is its **own** completed set (2 members × 3 rounds = 6 logical sets, not 1). Overloading `set_group` would make `completedSetsFor` collapse a whole superset to one set — wrong. The two are orthogonal axes: `set_group` = "which logged rows are one set," `superset_group` = "which queue slots alternate." They compose cleanly (a superset member can be a drop-set exercise: its own drops still share a `set_group`). |
| 2 | **Session-scoped grouping (the override analog).** | Mirror `superset_group`/`superset_seq` onto `session_exercise_overrides`, exactly as `drop_count` was mirrored in v6. | The override row is the session's view of a slot (swap/skip/insert/drop_count all already round-trip through it — `active_workout_controller._applyOverrides`/`_buildQueue`). A superset slot must keep its group identity through a swap or a skip, and survive resume. No new table — same pattern as v5/v6. |
| 3 | **Membership shape.** | A superset is an **ordered set of contiguous program_exercises** sharing one `superset_group` uuid, ordered by `superset_seq` (0 = A1, 1 = A2…). Members keep their own `position`; the group sorts as a contiguous block by the min member `position`. | Reuses `position` ordering (the queue is position-sorted in `_buildQueue`). Contiguity keeps the queue render and the cursor walk simple — no interleaving of unrelated exercises. |
| 4 | **Cursor representation for rounds.** | Keep the existing flat `queue: List<PlannedExercise>` + `Cursor(exerciseIdx,setIdx)`. **Round = derived, not stored.** The "active member of the current round" is computed from `completedSetsFor` per member, exactly as the single-exercise cursor is today. | The flat queue + `cursorAfter` already resumes correctly from logged sets alone. Adding a stored "round index" would create a second source of truth that `cursorAfter` would have to reconcile — the same trap the v4 skip note warns about. Instead, the **round number for a member = its own completed-set count**, and the cursor advances to the next member in the group whose completed count is *behind* the round. This stays a pure function of `(queue, loggedSets)` → resumes for free. |
| 5 | **Rest behavior.** | Rest auto-starts **only after logging a set for the LAST member of a round** (`superset_seq == max in group`), OR after any set of a non-superset exercise (unchanged). Logging an inner member (A1 when A2 follows) does **not** start rest. | This is the whole point of a superset: you go A1→A2 back-to-back, rest once. Implemented as a predicate on the slot at log time; the watch mirrors it via `restDefaultSeconds`. |
| 6 | **Cursor walk order within a group.** | Round-major, member-minor: A1·r1 → A2·r1 → A1·r2 → A2·r2 → … When a member runs out of `targetSets` before its groupmates, it's skipped in later rounds (the round advances over it). | Matches how every lifter runs a superset. A member with fewer target sets naturally "falls out" — no special config (Non-goal: unequal-round UI). |
| 7 | **Drop-count composition.** | A superset member may have `drop_count > 0`. Its drop set is logged via the existing `logSetGroup` path (top+drops share a `set_group`), counts as one completed set for that member's round, then the round advances. | Orthogonality from Decision 1 means zero special-casing — `completedSetsFor` already counts distinct `set_group` keys. |
| 8 | **DB version bump.** | `_dbVersion` 6 → **7** in `lib/core/db/database.dart`; add `schemaV7Up` to `lib/core/db/migrations.dart`, wired into both `onCreate` (append after v6) and `onUpgrade` (`if (oldVersion < 7)`), mirroring the cumulative pattern. | Same shape as every prior migration; additive nullable columns, no backfill (NULL = "not in a superset," identical to how NULL `set_group` = singleton). |
| 9 | **Bridge schema bump.** | Pigeon `WatchExercise` gains `supersetGroup: String?` + `supersetSeq: int`; `WatchSessionSnapshot.schemaVersion` 3 → **4**. Regenerate via `dart run pigeon`. Watch model `WatchExerciseVM` decodes them as optional (stale snapshot from an older phone build still decodes — same forward-compat as `skipped`/`dropCount`). | The watch must render `A1/A2` and apply the round-rest rule. The fields are small and optional; the watch ignores unknown newer snapshot versions (per the `schemaVersion` contract in `pigeons/watch_bridge.dart`). |

## 4. Design & UX

### Day editor (`lib/features/programs/presentation/day_editor_screen.dart`)

The day editor is a `ReorderableListView` of `_ExerciseTile`s. Supersets add a **grouping affordance in edit mode** and a **visual bracket** in view mode. Members render with an `A1/A2` prefix pill (reusing `MetaPill` from the existing tile) and a left accent rail (`LsAccent`) spanning the grouped tiles.

**Forming a group:** in edit mode (`_editing == true`), a new per-tile action "**＋ SUPERSET**" attaches the tile to the one **above** it (or starts a 2-member group with it). Ungroup via "✕ SUPERSET" on a grouped tile. (Selection-based multi-grouping is a fast-follow; adjacent-attach keeps v1 minimal and matches the contiguity constraint, Decision 3.)

```
DAY EDITOR (edit mode)                 DAY EDITOR (view mode)
┌───────────────────────────────┐      ┌───────────────────────────────┐
│ ⠿  BENCH PRESS                 │      │ ┃ A1  BENCH PRESS              │
│    [3 SETS][8-12 REPS][60 KG]  │      │ ┃     3·8-12·60KG             │
│    ＋ SUPERSET                 │      │ ┃ A2  BB ROW                  │
├───────────────────────────────┤      │ ┃     3·8-12·50KG    SUPERSET │
│ ⠿  BB ROW            [A2]      │      ├───────────────────────────────┤
│    [3 SETS][8-12 REPS][50 KG]  │      │   SQUAT                       │
│    ✕ SUPERSET                  │      │   3·5·100KG                   │
├───────────────────────────────┤      └───────────────────────────────┘
│ ⠿  SQUAT                       │
│    [3 SETS][5 REPS][100 KG]    │
│    ＋ SUPERSET                 │
└───────────────────────────────┘
```

- The `A1/A2` pill reuses `MetaPill`; the bracket rail uses `t.accent.accent`.
- Reorder still works (drag handle = `ReorderableDragStartListener`); reordering a member **out of contiguity dissolves the group** (or is blocked) — simplest: dragging a non-member into the block, or a member out, ungroups. v1: keep it blunt — moving a member out of its run clears its `superset_group`.

### Active workout (`lib/features/workout/presentation/active_workout_screen.dart`)

The current exercise card shows the **round context** when the active slot is a superset member: a header strip `SUPERSET A · ROUND 2 OF 3` and a compact `A1 ✓ · A2 ▸` member strip so the lifter knows what's next without scrolling. Logging a set advances to the next member in the round (no rest), or — on the last member — starts rest and advances to the first member's next round.

```
ACTIVE WORKOUT (superset member active)
┌───────────────────────────────────────┐
│  SUPERSET A · ROUND 2 / 3             │
│  A1 BENCH  ✓   A2 BB ROW ▸            │  ← member strip, ▸ = active
│                                        │
│            BB ROW                      │
│        TARGET 8-12 · 50 KG             │
│                                        │
│   [ crown dial reps / weight / RIR ]   │
│            ◉  LOG SET                   │
│                                        │
│  after this (last member) → REST 90s   │
│  then → A1 BENCH, round 3              │
└───────────────────────────────────────┘
```

- Logging A1 (inner member) → **no rest**, cursor jumps to A2, same round.
- Logging A2 (last member) → **rest starts**, cursor returns to A1 for the next round.
- The existing rest timer + Live Activity (`live_activity_controller.dart`) are unchanged — they only fire when the controller decides rest starts (Decision 5).
- A skipped member (durable skip via `session_exercise_overrides.skipped`) is walked past in every round; the round strip shows it struck through. This rides the existing `skipped` plumbing.

### Watch (`ios/LSWatch Watch App/`)

`CurrentExerciseView.swift` / `SetLoggerView.swift` render the active member; `WatchWorkoutModel.swift` already advances on `completedGroups >= targetSets` and walks past `isSkipped`. The model gains a **round-aware next-member** step: after a logged set, if the active slot is a superset inner member, advance to the next non-skipped member in the group **without** starting rest; on the last member, advance to the first member's next round **and** start rest (`restDefaultSeconds`). The `A1/A2` label + `ROUND n/N` render in `CurrentExerciseView`. Swapping/skipping/forming groups stays **phone-only** (consistent with how swap and skip are phone-only today — `WatchExerciseVM.isOverridden` / `isSkipped` are read-only on the watch).

## 5. Data & schema changes

**Migration — add `schemaV7Up` to `lib/core/db/migrations.dart`** (mirror the cumulative comment style of v5/v6):

```dart
/// v7: supersets, surfacing the program-level grouping the v6 set-group note
/// promised. A superset is an ordered set of CONTIGUOUS program_exercises
/// sharing one `superset_group` uuid, ordered by `superset_seq` (0 = A1, 1 =
/// A2 …). NULL `superset_group` = a normal standalone exercise (no backfill —
/// identical to how a NULL `set_group` is a singleton).
///
/// This is a DIFFERENT axis from `workout_sets.set_group` (v6): `set_group`
/// groups logged ROWS into one completed set (drop sets); `superset_group`
/// groups queue SLOTS into alternating rounds. They compose — a superset
/// member can itself be a drop-set exercise. Carried on the override too
/// (like `drop_count`) so the grouping survives a mid-session swap/skip and
/// a resume/watch-resync.
const schemaV7Up = <String>[
  'ALTER TABLE program_exercises ADD COLUMN superset_group TEXT',
  'ALTER TABLE program_exercises ADD COLUMN superset_seq INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE session_exercise_overrides ADD COLUMN superset_group TEXT',
  'ALTER TABLE session_exercise_overrides ADD COLUMN superset_seq INTEGER NOT NULL DEFAULT 0',
];
```

**`lib/core/db/database.dart`:** bump `const _dbVersion = 6;` → `7`; add `for (final stmt in schemaV7Up) { batch.execute(stmt); }` to `onCreate` after the v6 block; add `if (oldVersion < 7) { for (final stmt in schemaV7Up) { batch.execute(stmt); } }` to `onUpgrade`.

**Settings/flags:** none. No `settings_repository.dart` change.

**Watch bridge / Pigeon (`pigeons/watch_bridge.dart`):**
- `WatchExercise` gains `String? supersetGroup;` and `int supersetSeq;`.
- `WatchSessionSnapshot.schemaVersion`: bump the value pushed from `lib/features/workout/application/watch_snapshot.dart` from 3 → 4.
- Regenerate: `dart run pigeon --input pigeons/watch_bridge.dart` → updates `lib/features/workout/application/watch_bridge.g.dart` + `ios/Runner/WatchBridge.g.swift`.
- `ios/LSWatch Watch App/WatchWorkoutModel.swift`: `WatchExerciseVM` adds `var supersetGroup: String?` and `var supersetSeq: Int?` (optional → forward-compat with older snapshots, exactly like `skipped`/`dropCount`).

## 6. Implementation plan

Ordered by layer. Name the specific files.

1. **DB** — `lib/core/db/migrations.dart` (`schemaV7Up`); `lib/core/db/database.dart` (version + onCreate/onUpgrade wiring).
2. **`domain/`** —
   - `lib/features/programs/domain/program_exercise.dart`: add `supersetGroup` (`String?`) + `supersetSeq` (`int`, default 0) to `ProgramExercise` (ctor, `copyWith`, `fromRow`, `toRow`), mirroring `dropCount`.
   - `lib/features/workout/domain/active_session.dart`: add `supersetGroup`/`supersetSeq` to `PlannedExercise` (+ `fromView`, `copyWith`); add a derived helper `bool get isSuperset => supersetGroup != null`. Add a **pure top-level round helper** next to `completedSetsFor`:
     - `int roundFor(List<PlannedExercise> queue, List<WorkoutSet> logged, int memberIdx)` and
     - the **cursor walk** changes (see step 4) so the round logic is unit-testable in isolation (mirrors how `cursorAfter`/`insertOrderPosAfter` are top-level pure functions).
3. **`data/` (DAO)** —
   - `lib/features/programs/data/program_dao.dart`: `addProgramExercise`/`updateProgramExercise` accept `supersetGroup`/`supersetSeq`; add `setSuperset(List<String> programExerciseIds)` (assign one uuid + 0..N seq) and `clearSuperset(String programExerciseId)` (NULL the group, renumber survivors). `listProgramExercises` already `SELECT pe.*` so the new columns flow through `fromRow` for free.
   - `lib/features/workout/data/workout_dao.dart`: `upsertOverride`/`insertSessionExercise` carry `supersetGroup`/`supersetSeq` (mirror `dropCount` at lines ~269/326); the override `fromRow` (~line 399) reads them.
4. **`application/` (controller)** — `lib/features/workout/application/active_workout_controller.dart`:
   - Extend `cursorAfter` to be **round-aware**: instead of "first member behind target," compute the active `(memberIdx, round)` for a superset group as the **first member whose completed-set count is less than the group's current round**, where the group round = `min(completedSetsFor across members)`. Standalone exercises are unchanged (a singleton "group of one" → identical behavior, so existing tests stay green).
   - In `logSet` / `logSetGroup` / `applyWatchLogSet`: after logging, decide rest via Decision 5 (`isLastMemberOfRound`) and advance the cursor to the next member-or-round via the new walk. Drop-set members continue to go through `logSetGroup`.
   - `_applyOverrides` / `_buildQueue`: copy `supersetGroup`/`supersetSeq` from the override onto the `PlannedExercise` (one line each, beside `dropCount`).
5. **`presentation/` (UI)** —
   - `lib/features/programs/presentation/day_editor_screen.dart`: superset bracket rail + `A1/A2` pills + "＋/✕ SUPERSET" edit actions; call `setSuperset`/`clearSuperset`.
   - `lib/features/workout/presentation/active_workout_screen.dart`: `SUPERSET A · ROUND n/N` strip + member strip; drive the next-member affordance off the controller's round state.
   - `lib/features/workout/presentation/program_status_sheet.dart`: render grouped members under their `A1/A2` bracket (it already renders skipped slots struck-through).
6. **Watch (Swift)** —
   - `pigeons/watch_bridge.dart` + regenerate (step in §5).
   - `lib/features/workout/application/watch_snapshot.dart`: project `supersetGroup`/`supersetSeq` into `WatchExercise`; bump `schemaVersion` to 4.
   - `ios/LSWatch Watch App/WatchWorkoutModel.swift`: round-aware advance + round-rest rule (mirror controller §4); `CurrentExerciseView.swift` renders `A1/A2` + `ROUND n/N`.

## 7. Acceptance criteria

- [ ] In the day editor, two adjacent exercises can be grouped into a superset and shown as `A1/A2`; grouping persists across app restart (reads back from `program_exercises.superset_group`).
- [ ] Ungrouping a superset member clears its `superset_group` and renumbers survivors (a 3-member group losing A2 becomes A1/A2, contiguous seq).
- [ ] Starting a workout on a day with a superset builds a queue where the members are contiguous and carry their `supersetGroup`/`supersetSeq`.
- [ ] Logging proceeds **round-major**: A1·r1 → A2·r1 → A1·r2 → A2·r2 → … with the cursor landing on the correct member each time.
- [ ] **Rest fires only after the last member of a round** (A2 in a 2-member group), not after A1.
- [ ] A superset member with `drop_count > 0` logs its drop set as one completed set, then the round advances correctly.
- [ ] A member with fewer `targetSets` falls out of later rounds; remaining members continue without it.
- [ ] **Resume correctness:** killing and relaunching the app mid-superset restores the cursor to the exact `(member, round)` derived purely from logged sets (no stored round index).
- [ ] **Skip composition:** durably skipping a superset member walks the cursor past it in every round and survives resume/watch-resync (no snap-back).
- [ ] **Watch:** the watch renders `A1/A2 · ROUND n/N`, advances within a round, and starts rest only after the last member; a stale snapshot from an older phone build still decodes (optional fields).
- [ ] Drop sets, swaps, durable skip, and session inserts are **unchanged** for non-superset exercises (regression).

## 8. Testing

Unit tests (in-memory sqflite via `sqflite_ffi`; pure-function tests need no DB) — mirror `test/workout_progress_test.dart`, which already exercises `cursorAfter` and the drop-set `set_group` groups. Add a `group('supersets (round walk)')`:

- **`cursorAfter` over a 2-member superset, empty log → A1, round 1** (member 0, the first behind the group round).
- **A1·r1 logged → cursor on A2, round 1** (inner member advance, no finish).
- **A1·r1 + A2·r1 logged → cursor back on A1, round 2** (round-major wrap).
- **All rounds logged for both members → cursor past the group** (group complete → next standalone exercise or finished).
- **Unequal targets:** A1 `sets:2`, A2 `sets:3` — after 2 full rounds, A1 is done; round 3 lands on A2 alone, then finishes.
- **Drop-set member:** A1 has a drop set (top+drops sharing `set_group`) → counts as one completed set; cursor advances to A2 same round (reuses the existing `dropSet(ex, group)` helper in the test file).
- **Skip composition:** A2 skipped → `cursorAfter` walks A1·r1 → A1·r2 (never lands on A2); mirrors the existing "skip survives reconciliation" test.
- **Rest predicate:** a pure `isLastMemberOfRound(queue, idx)` returns false for A1, true for A2 — assert directly (no timer needed).
- **Standalone regression:** all existing `cursorAfter`, `WorkoutProgress.from`, and drop-set tests stay green (a non-superset exercise is a singleton group → identical paths).

DAO test (mirror `test/dao_test.dart` / `test/queries_test.dart`): `setSuperset` assigns one uuid + 0..N seq across given ids; `clearSuperset` NULLs and renumbers; the v6→v7 migration applies on an existing v6 DB without data loss (`onUpgrade` path).

Widget test: day-editor tile renders the `A1/A2` bracket for grouped rows; active-workout card renders `ROUND n/N`.

**Manual matrix (watch + reliability):** phone-define superset → start on watch → log a full superset on the wrist, confirming rest fires once per round and the round/member labels track; kill the phone app mid-round and confirm resume lands on the right `(member, round)`; confirm a superset member swap on the phone reflects on the watch read-only.

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Cursor walk gets a second source of truth (a stored round) that `cursorAfter` can't reconcile on resume — the exact v4 "skip evaporates" trap. | Medium | **Decision 4:** round is *derived* from logged sets, never stored. Resume is a pure function of `(queue, loggedSets)`. Tested directly. |
| Overloading `set_group` collapses a superset to one completed set. | High (if naively reused) | **Decision 1:** a distinct `superset_group` axis; `completedSetsFor` (per `set_group`) is untouched. |
| Drop-set × superset composition bug (the two groupings interfere). | Medium | Orthogonality by construction (Decision 7) + an explicit drop-set-member unit test. |
| Watch and phone disagree on whether rest should fire mid-round. | Medium | Single rule (`isLastMemberOfRound`) implemented identically on both sides, driven by `restDefaultSeconds`; covered by the manual watch matrix. |
| Day-editor grouping UX feels heavy / breaks reorder. | Low-Medium | v1 is adjacent-attach + blunt "drag-out ungroups," contiguity-only. Defer selection-based multi-group. |
| Scope creep into a circuit/EMOM builder. | Medium | Explicit Non-goals in §1; no time-based or round-count config ships. |
| Migration applied to a live v6 DB drops data. | Low | Additive nullable columns only, no backfill; `onUpgrade` `if (oldVersion < 7)` mirrors every prior migration; tested on a seeded v6 DB. |

## 10. Definition of done

- A user can define a superset in the program, log it as alternating rounds on **both phone and watch** with rest firing once per round, and it survives kill/relaunch and watch-resync — all on the **free** tier.
- The set-group note's promise is fulfilled: `lib/core/db/migrations.dart` v6 said the primitive was "supersets later"; v7 surfaces the program-level grouping that completes it, with the runtime `set_group` untouched.
- Positioning claim unlocked: removes the "no supersets" recommendation asterisk vs. Strong/Hevy/Jefit ([00-competitive-analysis.md](../00-competitive-analysis.md)), and **surpasses** by being the only RIR-or-watch app delivering superset round-logging on the wrist ([01-strategy-and-positioning.md](../01-strategy-and-positioning.md)).
- Update [02-roadmap.md](../02-roadmap.md): flip **SOW-08** Status to `✅ Shipped` and add a baseline row to "Already shipped" (Supersets — program-level `superset_group`, phone + watch, DB v7 / bridge schema v4).
