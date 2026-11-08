# SOW-13 — Copy a program or a day

> **Status:** 🟦 Built (1.5.0+13) — simtest QA pending · **Phase:** 1 · **Tier:** Free
> **Owner:** berke · **Est. size:** S
> **Strategic rationale:** a lifter who wants to try a variation of a working program today has to rebuild it by hand, exercise by exercise. One-tap copy keeps the "minimal, fast" promise ([01-strategy-and-positioning.md](../01-strategy-and-positioning.md)) for program editing, not just logging.

Follows the [SOW-00 template](SOW-00-template.md). Ships in 1.5.0 together with [SOW-14](SOW-14-exercise-variants.md), but **stands alone**: the SOW-13 commits come before any SOW-14 code, need no schema change, and leave the app shippable on their own.

---

## 1. Goal & Constraints
- **Delivers:** a **Duplicate program** action in the program editor and a **Duplicate day** action in the day editor. Each asks for a name (prefilled `<NAME> COPY`), creates a deep, independent copy and lands in the copy's editor.
- **Also delivers (H5, DEC-0007):** deleting a program or a day that has logged workouts no longer fails. The workouts are **kept and detached** from the program; History shows them as plain `WORKOUT` entries with every set intact.
- **Hard constraints:** no schema change; free; phone only; history, PRs and Stats keep working across the copy.
- **Non-goals:** no lineage column linking a copy to its source (so "vs last" does not carry over to a copied day — see §9); no copy of sessions, sets or session overrides; no share/import of programs (that is [SOW-12](SOW-12-data-import.md)).

## 2. Competitive context
Strong, Hevy and Boostcamp all let you duplicate a routine; it is table stakes. "Match" is enough here — we match it with one tap and no extra screen.

## 3. Locked decisions
| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | What a copy shares | Same `exercises` rows (shared library, `name UNIQUE`) | PRs (`pr_detector.dart`), Stats (`stats_provider.dart`), last-set prefill and the repeat chip (`workout_dao.dart` `lastSetForExercise`) are keyed by `exercise_id`, so history follows the movement into the copy for free. |
| 2 | What a copy owns | New uuid rows for `programs`, `program_days`, `program_exercises` (and, once SOW-14 lands, `program_exercise_variants`) | Editing or deleting the copy never touches the original. |
| 3 | Day copy placement | Same program, appended last | Mirrors `createDay`. |
| 4 | Naming | Prompt prefilled `<NAME> COPY`; cancel or empty name = no-op | Same pattern as NEW PROGRAM / RENAME. Duplicate names are allowed (they already are). |
| 5 | Delete a program/day with logged workouts (H5) | Keep sessions, null `workout_sessions.program_day_id` inside the delete transaction | Today the delete throws (FK on `program_day_id`, no `ON DELETE`). Copying makes "copy, then delete the old one" likely. No `ALTER TABLE`, no migration. |

## 4. Design & UX
- **Program editor** (`program_editor_screen.dart`): `LsTopbar.trailing` gets `LsIconSquare(Icons.copy_all, semanticLabel: 'Duplicate program')`. Flow: prompt `DUPLICATE PROGRAM` → copy → `pushReplacement('/programs/<copy>')` → snackbar *"Copied. Changes here don't touch <ORIGINAL>."*
- **Day editor** (`day_editor_screen.dart`): same icon, `semanticLabel: 'Duplicate day'`, prompt `DUPLICATE DAY` → copy → `pushReplacement('/programs/<p>/days/<copy>')`, same snackbar wording with the day name.
- The copy is newest, so it becomes the default program on Start Workout (`listPrograms` is `created_at DESC`). That is intended — you copy a program to train it.

## 5. Data & schema changes
**No schema change.** `ProgramDao.deleteProgram` / `deleteDay` become transactions that first run `UPDATE workout_sessions SET program_day_id = NULL WHERE program_day_id IN (<affected days>)`, then delete (days and slots cascade as before).

An *active* session can be detached too (the editor is reachable mid-workout). The in-memory workout keeps running and can be finished normally. If the app is killed first, `ActiveWorkoutController._resumeIfPossible` finds an active session with no day; it now **completes** it when it has logged sets (so they stay in History) and abandons it otherwise. Before this change such a session would have blocked every new workout ("A workout is already in progress").

## 6. Implementation plan
1. `data/program_dao.dart`: `duplicateProgram(programId, {name})`, `duplicateDay(dayId, {name})` — one `transaction` each, positions kept, `created_at = now`. `deleteProgram` / `deleteDay` detach sessions first (H5).
2. `application/active_workout_controller.dart`: resume handles a detached active session (§5).
3. `presentation/program_editor_screen.dart`, `day_editor_screen.dart`: topbar icon, prompt, `pushReplacement`, snackbar; invalidate `programsListProvider` / `programDaysProvider`.

## 7. Acceptance criteria
- [ ] Duplicating a program copies every day, slot, target, weight step and drop count in order; every id is new; `exercise_id`s are the same.
- [ ] Editing or deleting anything in the copy leaves the original unchanged.
- [ ] Duplicating a day appends it to the same program.
- [ ] Cancelling or clearing the prompt creates nothing.
- [ ] An empty program/day copies without error.
- [ ] Deleting a program or day with completed workouts succeeds; the workouts stay in History (as `WORKOUT`), sets intact.

## 8. Testing
- `test/program_copy_test.dart` (in-memory sqflite via `test/support/test_db.dart`): deep equality, new ids, same exercise ids, independence, day appended last, empty program.
- `test/dao_test.dart`: delete program/day with a completed session keeps the session and nulls its day.
- Widget test: the duplicate icon is present by semantics label; cancelling the prompt creates nothing.
- Manual (simtest, plan §F): CP-01…CP-06.

## 9. Risks & mitigations
| Risk | Likelihood | Mitigation |
|---|---|---|
| Copied day shows no "vs last" on its first session | Certain | Expected: comparisons are per day id. PRs and Stats still carry over. A lineage column can come later. |
| User deletes the original and loses the program label on old workouts | Med | Sets, PRs and Stats are untouched; only the History heading falls back to `WORKOUT`. |

## 10. Definition of done
Analyze clean, tests green, simtest CP-01…CP-06 pass. Mark SOW-13 in [02-roadmap.md](../02-roadmap.md).

## 11. Build notes (deviations from the 2026-11-08 plan)
- **Commit order.** The SOW-13 steps (duplicate DAO, entry points) were committed *before* the v7 schema and variant DAO, so `docs → shared schema helper → duplicate → entry points` is a schema-free prefix that ships on its own. Variant copying was added to `_copySlots` together with the variant DAO (SOW-14).
- **H5 lives in the "shared schema helper" commit**, as the plan's characterization test turned into a passing test: the plan's suspicion (A5) was confirmed — the old delete threw `FOREIGN KEY constraint failed`.
- **Detached active session.** Not in the plan: an active workout whose day is deleted would otherwise block every new workout after a relaunch. Smallest fix: complete it on resume if it has sets, else abandon (§5).
- **Day copy position** uses `MAX(position) + 1`, not the row count `createDay` uses, because deleting a day leaves gaps.
