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
| 4 (H4) | First session of an exercise/variant | **FIRST TIME** label, PR badge suppressed — in the summary, History detail, the share card and the share text (DEC-0007 #10) | Otherwise every new variant produces a guaranteed fake weight PR. |
| 5 | Where the switch lives | **Exercise-options menu** (DEC-0007), not a chip row under the title | Every other in-workout edit already lives there; keeps the screen clean. |
| 6 | Set target after a switch | Carried over: remaining sets of the slot move to the new exercise | Plan 3 sets, 1 done on the machine, switch to the bar → bar target 2. |
| 7 | Badge under the title | On a slot with variants, `VARIANT OF <BASE>` (on a variant) replaces `SUBSTITUTED · WAS X`; on the base nothing is shown — no badge, no gap (DEC-0007 #12); a swap to a non-member keeps `SUBSTITUTED · WAS X` | The badge says which variant is active; the base needs no label (the switch is one menu away). |

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
- Switching back to the base drops the override (tune button back to neutral) only when the round trip left no trace: nothing logged on any variant, and sets, reps, drops, weight and step all as planned. A member's session weight (e.g. a "Change exercise" weight edit) is remembered when the slot switches away from it and restored when it switches back — in memory only: after a resume just the current member's weight is known (one override row per slot).
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
- **Day rule (D-0011, dispatcher default — to confirm with Berke):** within one program day an exercise is used **at most once as a variant, and never as both a variant and a base**. The DAO enforces it in every direction and throws `VariantConflict` (shown inline in the variants sheet, as a snackbar in the day editor and the summary): `addVariant` / `editVariant` (`sameAsBase`, `duplicate`, `baseOfAnotherSlot`, `variantOfAnotherSlot`), `addProgramExercise` and a base rename in `updateProgramExercise` (`variantOfAnotherSlot`; a write that keeps the slot's exercise — a summary raise — is never refused), and the summary's ADD TO DAY / SAVE AS VARIANT for an exercise inserted or swapped into the workout (refused → stays pending). Two slots sharing the same **base** stay allowed, as in 1.4.1 (that pre-existing case still pools sets by exercise, unchanged).
  - **Read guard:** a day that already breaks the rule (written before it, e.g. a 1.4.1 rename of a base to its own or another slot's variant) is not migrated; `listVariantsForDay` / `listVariants` hide the conflicting variant — the base wins, else the first variant in day order — and `PlannedExercise.members` dedupes by exercise as a last line of defence, so the picker never shows a dead duplicate row. `duplicateProgram` / `duplicateDay` don't copy such a variant, so a copy looks exactly like its source.
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
- [ ] Adding a variant equal to the base, a duplicate, or another slot's base or variant on the same day is rejected with a message; so is adding (or renaming) a slot's base to an exercise that is a variant on that day.
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
- Summary (`test/summary_apply_state_test.dart`): raiseVariant / addVariant apply + undo, no ADD for variants, inserted still ADD, apply-all counts; first-exposure suppression; a refused ADD stays pending; swap-chain attribution.
- Fix round D-0011: day rule + read guard (`variants_dao_test`, `program_copy_test`, `program_duplicate_widget_test`), complete-slot switch and switch-back rules (`variant_switch_test`, `variant_menu_widget_test`), orphaned workout on resume / delete + warning (`orphan_workout_test`), variant card layout with real fonts at 390pt and the UNDO snackbar lifecycle (`summary_screen_widget_test`).
- **Manual (simtest, plan §F), updated for the menu placement:**
  - **VAR-03:** in the active workout, open the tune (exercise options) menu: **Switch variant** is listed only on the slot that has variants; on other slots it is absent.
  - **VAR-04:** Switch variant → pick the machine variant → title, WT pill (40 kg) and the badge (`VARIANT OF …`) update; reopening the menu → Switch variant shows the machine row marked current; the repeat chip uses the variant's history.
  - **VAR-12:** light theme: screenshots of the options menu with the Switch variant entry, the variant picker sheet, and the variants editor sheet.
  - **Fix round D-0011 — new and changed checks:**
    - **VAR-13 (day rule, A):** on a day where OVERHEAD PRESS has the variant SHOULDER PRESS (MACHINE): (a) LATERAL RAISE → Variants → + ADD VARIANT 'Shoulder Press (Machine)' → inline "… is already a variant of another exercise on this day.", nothing added; (b) day editor + EXERCISE 'Shoulder Press (Machine)' → snackbar with the same message, no new slot; (c) rename LATERAL RAISE's base to 'Shoulder Press (Machine)' → same message, slot unchanged; (d) a variant equal to another slot's base is still refused ("already its own exercise on this day"); (e) two slots with the same base can still be added (1.4.1 behaviour). **RISK-02** becomes: sharing a variant across two slots is refused at (a); its old repro can no longer be built.
    - **VAR-14 (complete slot, B):** plan 3, log all 3 on the base, NEXT → back to the slot (PREV), open the tune menu: **Switch variant** is shown dimmed with "ALL SETS DONE ON <BASE>" and does nothing; the slot still shows 3 SETS. Mid-slot switching (VAR-05/06, RISK-01) unchanged.
    - **VAR-15 (switch back keeps edits, C):** on the base, Change exercise → same name, weight 40 → 42.5 → SAVE; Switch variant → MACHINE → back to the base: WT pill 42.5 kg, tune button still tinted. And: switch to MACHINE, Add set, log 1, switch back: tune button stays tinted and the banner reads PREVIOUSLY 1 SET ON SHOULDER PRESS (MACHINE).
    - **RISK-05 (delete with a running workout, D) — rewritten:** with a set logged, Home → Programs → swipe the program → the DELETE? dialog adds "Your workout in progress is on this program. Deleting ends it now; sets logged so far stay in History." (same for a day in the program editor: "… on this day."); DELETE → Home shows **START WORKOUT** at once (no RESUME), the Live Activity is gone, no rest banner; History lists the session ('WORKOUT', its sets) with a duration that ends at the last set, not at the delete. Cold-start path (the app died before the delete could close the workout): with a set logged and a rest running, terminate the app, `sqlite3 … "UPDATE workout_sessions SET program_day_id = NULL WHERE status = 'active'"`, launch → START WORKOUT, no rest banner, Live Activity gone, the session `completed` with `ended_at` = its last set's `logged_at`.
    - **VAR-16 (repeat chip, G = VAR-04's failing clause):** workout C: switch to a variant with no history, log 20×10, finish; workout D in the SAME app process: switch to it again → 'Repeat last set, 20×10' is shown.
    - **VAR-08 (H):** the un-applied card reads the full 'SHOULDER PRESS (MACHINE)' (wrapping to 2 lines) and 'VARIANT TARGET 40 → 42.5 KG' (wrapping below the label if needed) in dark and light; no separate VARIANT tag; after apply 'UPDATED'.
    - **VAR-17 (UNDO snackbar, I):** APPLY ALL → the 'N program targets updated · UNDO' snackbar disappears after ~5 s even with the XCUITest driver attached (accessibility on); apply one and tap Done at once → no snackbar on Home or in the next workout.

  - **Round D-0013 — new and changed checks:**
    - **VAR-18 (no base hint, DEC-0007 #12):** on a slot with variants running its base, nothing is shown under the title (no `BASE · N VARIANTS`, no empty gap: the meta pills sit where they sit on a slot without variants); switch to a variant → `VARIANT OF <BASE>` in the accent colour; back to the base → gone again. VAR-04's badge clause is unchanged.
    - **Polish (QA observations of the 2026-11-08 retest):** VAR-17 in the DARK theme — the snackbar's UNDO label is clearly readable (dark on the light snackbar; light on dark in LIGHT); VAR-14 — the dimmed row reads the whole 'ALL SETS DONE ON <BASE>' (wrapping); VAR-15 — after the 40 → 42.5 edit the picker lists the base as '42.5 KG · BASE · CURRENT', and after switching away and opening the picker again the base row still shows 42.5; RISK-05 cold path — Home's LAST strip shows the closed session on the same launch.
    - **VAR-19 (FIRST TIME everywhere, DEC-0007 #10):** finish a workout with a variant logged for the first time and a lift that beat its history: the summary card reads FIRST TIME / PR as before; then History → that session: FIRST TIME beside the new variant's name, nothing beside the others; the share card (from History and from the summary) shows FIRST TIME on the new variant and the PR box only on the real record, and the PR total counts only the real record; the share text reads `(first time)` on that line.

## 9. Risks & mitigations
| Risk | Likelihood | Mitigation |
|---|---|---|
| Downgrade to 1.4.1 then back crashes the v7 step | Med (Berke flips builds) | `IF NOT EXISTS`, no `ALTER`; test reopens a DB forced to `user_version = 6`. |
| Watch shows a stale exercise right after a switch | Low | A set is attributed by its own `exerciseId` (as with a swap); the snapshot listener pushes the new queue. |
| Same variant on two slots of one day | — | Refused by the DAO (day rule, §5); pre-rule data is hidden on read. |
| Variant edited mid-workout | Low | Applies from the next start/resume (documented). |

## 10. Definition of done
Analyze clean, tests green, simtest VAR-01…VAR-17 + REG-01…REG-07 + RISK-01…05 pass. Mark SOW-14 in [02-roadmap.md](../02-roadmap.md); v7 taken (SOW-08/-09/-10 move to v8+).

## 11. Build notes (deviations from the 2026-11-08 plan)
- **Menu, not chip row (DEC-0007).** Plan step E9 ("variant chip row") became "variant entry in the edit menu": `ExerciseOption.switchVariant` + `showVariantPickerSheet` in `exercise_options_sheet.dart`, wired in `swap_exercise_button.dart`. QA steps VAR-03 / VAR-04 / VAR-12 are rewritten for it in §8.
- **No `planTargetSets` field.** "Back to the base drops the override" compares against the fresh plan row instead (sets *and* reps *and* drop count), which also catches a rep edit made earlier with "Change exercise".
- **"Another slot's base on the same day" is rejected in the DAO** (`VariantConflictReason.baseOfAnotherSlot`), not only in the UI, so attribution can never be ambiguous.
- **Attribution also follows `previous_exercise_id`**, so bar → machine → bar still attributes the machine sets to the slot's variant; inserted override rows never count as swaps.
- **`summary_apply_state_test` :112-127 is unchanged.** Its "Cable Fly" is logged with no override row, i.e. it is an *added* exercise and correctly stays ADD; the H3 path is covered by a new seed that really swaps via an override.
- **H4 everywhere (DEC-0007 #10, D-0013).** First planned as summary-only; now History detail (a `FIRST TIME` label beside the name), the share card (`FIRST TIME` instead of the PR box) and the share text (`(first time)`) use the same rule, `ExercisePR.countsAsPr` / `isFirstExposure`, and a first exposure is not counted in the PR total. On the first-ever workout the summary keeps its baseline line and no per-card label, while its share card, like History, labels every lift FIRST TIME.
- **QA polish (D-0013).** The snackbar action colour is the page ground (`snackBarTheme.actionTextColor = bg`), readable on the inverse-surface snackbar in both themes; the Switch variant subtitle wraps (3 lines); the variant picker shows each member's session weight (`PlannedExercise.sessionWeightOf`: current, else remembered, else planned); closing an orphaned workout (`_closeDetached`, both paths) invalidates Home's LAST, History and Stats providers.
- **No base hint (DEC-0007 #12, D-0013).** The `BASE · N VARIANTS` line under the title is gone: on the base nothing is shown and the space collapses; a variant still reads `VARIANT OF <BASE>`.
- **Day rule (fix round D-0011, QA RISK-02 + review #1/#7).** The plan let one variant sit on two slots of a day ("the session override decides"); QA showed set counts, carry-over and the summary are keyed by exercise, so the slots pooled their sets. Rather than re-key everything by slot, an exercise is now used at most once per day as a variant (§5). Pre-rule rows are hidden, not migrated (1.4.1 had no variants).
- **Swap chains (review #6).** One override row per slot keeps only the last two links of a "Change exercise" chain (B → X → Y → Z keeps Z and Y). An exercise logged this session that matches no base, variant, override or insert must have been such a lost link, so the summary attributes it to the swapped slot (SAVE AS VARIANT) — **only when exactly one slot was swapped outside its members and no inserted exercise was swapped**. Known limitation: with two or more swapped slots (or a swapped insert) a lost link stays ADD TO DAY. Shared variants, the other half of #6, are gone with the day rule.
- **Summary card layout (QA VAR-08).** The UPDATE YOUR PROGRAM row lays its name and tag out in a `Wrap` (name up to 3 lines at full width, tag beside or below) and its target line as a `Wrap` of the label and an unbreakable-per-weight "old → new" run, so the proposed weight is never ellipsized; the separate `VARIANT` tag is dropped on a variant raise (the line already reads VARIANT TARGET). The lift card's name allows 3 lines and its inline action 2. Checked by a widget test with the app's real fonts at 390pt, both themes, a normal and a 44-character name.
- **Orphaned workout (review #4, QA RISK-05).** A workout whose program/day is deleted is closed by the delete itself (`closeIfDetached`, after a warning in the DELETE? dialog), or on the next resume if the app died first: completed with `ended_at` = its last set's `logged_at` (abandoned when empty), rest timer dismissed and every Live Activity ended (`endAllActivities` — a cold start doesn't know the old activity's id).
- **Carry-over on a complete slot (review #2).** No floor of 1: a complete slot carries nothing over and the menu disables Switch variant there, so round trips can't inflate the target.
- **Commit order:** the v7 migration and variant DAO were committed after SOW-13's commits (see SOW-13 §11).
