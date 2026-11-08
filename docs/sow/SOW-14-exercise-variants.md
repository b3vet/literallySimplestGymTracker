# SOW-14 — Exercise variants on a program slot

> **Status:** 🟦 Built (1.5.0+13) — simtest QA pending · **Phase:** 1 · **Tier:** Free
> **Owner:** berke · **Est. size:** L
> **Strategic rationale:** "the smith machine is taken" is the most common mid-workout edit. Today it means retyping the swap and guessing the weight every time. Pre-planned variants make it two taps and keep the numbers honest, which supports the speed claim in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md).

Follows the [SOW-00 template](SOW-00-template.md). Product decisions: DEC-0007 (H1–H5 accepted with the plan defaults; the switch lives in the exercise-options menu, **not** in a chip row).

---

## 1. Goal & Constraints
- **Delivers:**
  - A program slot (program exercise) keeps its **base** exercise and can hold 0..N **variants** — each an ordinary exercise (e.g. "Shoulder Press (Machine)") with its **own target weight and weight step**. Sets, reps and drop count come from the slot.
  - In the active workout, the **exercise-options menu** (the tune button at the top left, `SwapExerciseButton`) gets a **Switch variant** entry when the slot has variants. It lists base + variants, marks the current one, and switches in one tap.
  - The summary understands variants: it offers **VARIANT TARGET → W** for a variant that beat its target (never "ADD TO DAY"), and **SAVE AS VARIANT OF X** for an exercise swapped in with "Change exercise" (H3).
  - First-ever session of any exercise or variant shows **FIRST TIME** instead of a guaranteed fake PR (H4).
- **Hard constraints:** additive, idempotent DB migration (v7); no watch schema change; export format unchanged; free.
- **Non-goals:** switching variants from the watch; variants in onboarding templates; library-wide variants ("Machine Press is always a variant of Press"); pooling variant PRs/Stats into the base.

## 2. Competitive context
Hevy and Strong offer "replace exercise" per workout but forget it next time; Fitbod suggests substitutes but owns the plan. Nobody lets the lifter pre-plan "bar, or machine if the bar is taken" with per-equipment targets. That is the "surpass".

## 3. Locked decisions
| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 (H1) | PR / Stats / target attribution | **Per variant** — a machine PR is not a bar PR | Loads on different equipment are not comparable; `PrDetector` and `stats_provider` are already per `exercise_id`; no data migration. |
| 2 (H2) | Scope of a variant | **Per program slot** | Each slot has its own target weight; copies with the program (SOW-13). |
| 3 (H3) | Summary for a mid-workout "Change exercise" | **SAVE AS VARIANT OF X**; exercises *inserted* into the session still get ADD TO DAY | A swap is almost always "same slot, other equipment". |
| 4 (H4) | First session of an exercise/variant | **FIRST TIME** label, PR badge suppressed (summary only) | Otherwise every new variant produces a guaranteed fake weight PR. |
| 5 | Where the switch lives | **Exercise-options menu** (DEC-0007), not a chip row under the title | Every other in-workout edit already lives there; keeps the screen clean. |
| 6 | Set target after a switch | Carried over: remaining sets of the slot move to the new exercise | Plan 3 sets, 1 done on the machine, switch to the bar → bar target 2. |
| 7 | Badge under the title | On a slot with variants, `VARIANT OF <BASE>` (on a variant) or `BASE · N VARIANTS` (on the base) replaces `SUBSTITUTED · WAS X`; a swap to a non-member keeps `SUBSTITUTED · WAS X` | The badge says which variant is active and hints that variants exist (the switch is one menu away). |

## 4. Design & UX
### Program side
- **Day editor tile:** `MetaPill('+N', 'VAR')` next to SETS / REPS / KG / DROP when the slot has variants.
- **Exercise edit sheet (program mode):** a `VARIANTS · N ›` row between SAVE and DELETE. Tapping it saves the sheet's current values, then opens the **variants sheet**.
- **Variants sheet** (`variants_sheet.dart`, `LsSheet` + `LsSheetHeader('VARIANTS', <base name>)`): one card per variant (name + weight), tap = edit, swipe left = delete (same `Dismissible` + `confirmDelete` as the day list), `+ ADD VARIANT` button. Rejections show an inline message in the sheet.
- **Variant add/edit** reuses `showExerciseEditSheet(variantMode: true)`: only name, weight and weight step (SETS, REP MIN, REP MAX, DROP SET hidden). Autofill takes a program row's weight when one exists, else the exercise's last logged weight.

### Active workout
```
 [tune]   00:12:41   [≡]          tune → EXERCISE OPTIONS
 CURRENT LIFT            01/05      ┌──────────────────────────────┐
 SHOULDER PRESS (MACHINE)           │ ⇄ CHANGE EXERCISE          › │
 VARIANT OF SHOULDER PRESS          │ ⧉ SWITCH VARIANT           › │ ← only when the slot has variants
 [2 SETS] [8-12 REPS] [40 KG]       │   NOW: SHOULDER PRESS (MACH.) │
                                    │ + ADD SET … − REMOVE SET …    │
                                    │ INSERT EXERCISE · SKIP        │
                                    └──────────────────────────────┘
 SWITCH VARIANT → second sheet:  SHOULDER PRESS        60 KG · BASE
                                 SHOULDER PRESS (MACH.) 40 KG    ✓ current
                                 SHOULDER PRESS (DB)    22.5 KG
```
- Selecting a row switches at once (no confirm); selecting the current row just closes the sheet.
- Switching back to the base with nothing logged on the variant (and the plan's set count restored) drops the override, so the tune button goes back to neutral.
- `PREVIOUSLY N SETS ON X` banner stays. The repeat-last-set chip follows the active exercise automatically (it is keyed by `exerciseId`).
- Skipped and inserted slots never show the entry. Variant edits made during a workout apply from the next start/resume (the queue is fixed at start).

## 5. Data & schema changes
**DB v7 (additive, idempotent):**
```sql
CREATE TABLE IF NOT EXISTS program_exercise_variants (
  id TEXT PRIMARY KEY,
  program_exercise_id TEXT NOT NULL REFERENCES program_exercises(id) ON DELETE CASCADE,
  exercise_id TEXT NOT NULL REFERENCES exercises(id),
  position INTEGER NOT NULL,
  default_weight REAL NOT NULL,
  weight_step REAL,
  UNIQUE (program_exercise_id, exercise_id));
CREATE INDEX IF NOT EXISTS idx_pev_pe ON program_exercise_variants(program_exercise_id, position);
```
- `IF NOT EXISTS` on both, no `ALTER TABLE`: sqflite rewrites `user_version` on downgrade without calling a hook, so 1.4.1 → 1.5.0 → 1.4.1 → 1.5.0 re-runs the v7 step against an existing table.
- No mirror column on `session_exercise_overrides` (an override already stores `exercise_id`, `default_weight`, `weight_step`).
- Watch Pigeon schema stays v3 (the snapshot already sends `exerciseId` + `name` per slot). Export stays JSON `version: 1`; variant sets export under their own exercise.
- Added to the dev-reset delete order (`maintenance.dart`).

## 6. Implementation plan
1. `core/db`: `schemaV7Up`, `_dbVersion = 7`, shared `createSchema` / `upgradeSchema`.
2. `programs/domain/program_exercise_variant.dart`: `ProgramExerciseVariant` + `ProgramExerciseVariantView`.
3. `programs/data/program_dao.dart`: `listVariants`, `listVariantsForDay`, `addVariant` / `updateVariant` (reject base, duplicate, or another slot's base on the same day — `VariantConflict`), `deleteVariant`; `updateProgramExercise` deletes a variant that became the base; `duplicateProgram` / `duplicateDay` copy variants.
4. `programs/presentation`: `exercise_edit_sheet.dart` (`variantMode`, `variantCount`, `manageVariants` result), `variants_sheet.dart`, `day_editor_screen.dart` (pill + flow).
5. `workout/domain/active_session.dart`: `PlannedExercise` gets `baseExerciseId/Name`, `baseDefaultWeightKg`, `baseWeightStepKg`, `variants` (`SlotVariant`).
6. `workout/application/active_workout_controller.dart`: variants loaded on start/resume, pure `carryOverTargetSets`, `switchVariant`.
7. `workout/presentation`: `exercise_options_sheet.dart` (`ExerciseOption.switchVariant`, `showVariantPickerSheet`), `swap_exercise_button.dart`, `active_workout_screen.dart` badge.
8. `workout/application/summary_controller.dart` + `summary_screen.dart`: attribution (base match → this session's override → first slot holding the variant), `raiseVariant` / `addVariant` kinds, wording; `pr_detector.dart` `isFirstExposure`.

## 7. Acceptance criteria
- [ ] Fresh install and v6 → v7 upgrade both create the table; reopening after a forced downgrade to v6 does not fail; all v6 rows survive.
- [ ] Adding a variant equal to the base, a duplicate, or another slot's base on the same day is rejected with a message.
- [ ] Renaming a slot's base to one of its variants removes that variant.
- [ ] Deleting a slot, day or program cascades its variants.
- [ ] The **Switch variant** menu entry appears only on a non-inserted, non-skipped slot with ≥1 variant; it lists base + variants with the current one marked.
- [ ] Switching updates title, weight pill and badge; remaining sets carry over; the cursor advances when the variant's target is met; a resume rebuilds the same state.
- [ ] Switching back to the base with nothing logged on the variant clears the override (neutral tune button).
- [ ] Summary: a variant that beat its target offers VARIANT TARGET → W, apply changes only the variant row, undo restores it; a variant is never offered ADD TO DAY; a "Change exercise" swap offers SAVE AS VARIANT OF X and undo deletes exactly that variant; an inserted exercise still offers ADD TO DAY.
- [ ] First exposure of an exercise shows FIRST TIME, not PR; a raise is still offered when the target is beaten.

## 8. Testing
- DAO / migration (`test/variants_db_test.dart`): fresh DB, v6 → v7 with seeded rows, downgrade-then-reopen, cascade, `wipeAllData`, CRUD, rejections, ordering, base-becomes-variant.
- Controller (`test/variant_switch_test.dart`): carry-over table (0 done; 1 on base; back again; add set on variant; base target 1), override persistence + resume, cursor advance, revert on return.
- Widgets: `variantMode` hides set/rep pickers; variants sheet lists + adds; VARIANTS row returns `manageVariants`; options menu entry hidden without variants, lists base + variants with current marked, selecting calls `switchVariant`.
- Summary (`test/summary_apply_state_test.dart`): raiseVariant / addVariant apply + undo, no ADD for variants, inserted still ADD, apply-all counts; first-exposure suppression.
- **Manual (simtest, plan §F), updated for the menu placement:**
  - **VAR-03:** in the active workout, open the tune (exercise options) menu: **Switch variant** is listed only on the slot that has variants; on other slots it is absent.
  - **VAR-04:** Switch variant → pick the machine variant → title, WT pill (40 kg) and the badge (`VARIANT OF …`) update; reopening the menu → Switch variant shows the machine row marked current; the repeat chip uses the variant's history.
  - **VAR-12:** light theme: screenshots of the options menu with the Switch variant entry, the variant picker sheet, and the variants editor sheet.

## 9. Risks & mitigations
| Risk | Likelihood | Mitigation |
|---|---|---|
| Downgrade to 1.4.1 then back crashes the v7 step | Med (Berke flips builds) | `IF NOT EXISTS`, no `ALTER`; test reopens a DB forced to `user_version = 6`. |
| Watch shows a stale exercise right after a switch | Low | A set is attributed by its own `exerciseId` (as with a swap); the snapshot listener pushes the new queue. |
| Same variant on two slots of one day | Low | Session override decides the slot; else first slot wins. |
| Variant edited mid-workout | Low | Applies from the next start/resume (documented). |

## 10. Definition of done
Analyze clean, tests green, simtest VAR-01…VAR-12 + REG-01…REG-07 pass. Mark SOW-14 in [02-roadmap.md](../02-roadmap.md); v7 taken (SOW-08/-09/-10 move to v8+).

## 11. Build notes (deviations from the 2026-11-08 plan)
- **Menu, not chip row (DEC-0007).** Plan step E9 ("variant chip row") became "variant entry in the edit menu": `ExerciseOption.switchVariant` + `showVariantPickerSheet` in `exercise_options_sheet.dart`, wired in `swap_exercise_button.dart`. QA steps VAR-03 / VAR-04 / VAR-12 are rewritten for it in §8.
- **No `planTargetSets` field.** "Back to the base drops the override" compares against the fresh plan row instead (sets *and* reps *and* drop count), which also catches a rep edit made earlier with "Change exercise".
- **"Another slot's base on the same day" is rejected in the DAO** (`VariantConflictReason.baseOfAnotherSlot`), not only in the UI, so attribution can never be ambiguous.
- **Attribution also follows `previous_exercise_id`**, so bar → machine → bar still attributes the machine sets to the slot's variant; inserted override rows never count as swaps.
- **`summary_apply_state_test` :112-127 is unchanged.** Its "Cable Fly" is logged with no override row, i.e. it is an *added* exercise and correctly stays ADD; the H3 path is covered by a new seed that really swaps via an override.
- **H4 is summary-only**, as planned: History detail and its share card still read the raw `PrDetector`, so a first exposure can show PR there.
- **Commit order:** the v7 migration and variant DAO were committed after SOW-13's commits (see SOW-13 §11).
