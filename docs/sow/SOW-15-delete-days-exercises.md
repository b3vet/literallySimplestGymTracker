# SOW-15 — Delete a day or an exercise

> **Status:** 🟦 Built (1.5.0+15) — simtest QA pending · **Phase:** 1 · **Tier:** Free
> **Owner:** berke · **Est. size:** S
> **Strategic rationale:** removing a lift or a day from a program is basic editing. It existed only as a swipe in an EDIT mode that could not be reached, so users could not find it.

Follows the [SOW-00 template](SOW-00-template.md), shortened. Ships in 1.5.0 with [SOW-13](SOW-13-copy-programs.md) and [SOW-14](SOW-14-exercise-variants.md). DEC-0007 #14.

---

## 1. Problem
- Day rows (`program_editor_screen.dart`) and exercise rows (`day_editor_screen.dart`) had a `Dismissible` that worked only in EDIT mode. **EDIT mode could not be entered**: since the redesign, the EDIT button opened the rename prompt directly and `_editing` was never set to `true`. Swipe-to-delete was dead code.
- The exercise edit sheet's DELETE deleted with no confirm and no active-workout handling.
- **Bug found while characterizing:** deleting an exercise from the day of the workout in progress left the live queue unchanged (the slot stayed until a cold start). If it was the day's **last** exercise, the next cold start **abandoned** the session, which dropped its logged sets out of History, PRs and Stats (`_resumeIfPossible`: `planned.isEmpty → abandonSession`).

## 2. Behaviour
1. **EDIT mode.** The top-left EDIT button now toggles EDIT/DONE in both editors. Rename moved into EDIT mode: a **RENAME PROGRAM** / **RENAME DAY** button after the list.
2. **Visible delete control.** In EDIT mode each day row and exercise row shows a red remove button (`DeleteRowButton`, `dialogs.dart`). It is 44 × 44 pt and announced as "Delete <name>" with a tap action. A second tap while a delete is in flight (on the button, a swipe or DELETE DAY) is ignored, so dialogs never stack. It runs the same confirm → delete as the swipe, and the swipe still works. Outside EDIT mode the rows look and behave as before.
3. **DELETE DAY** (day editor, EDIT mode, after the exercise list) uses the program editor's confirm, including the workout-in-progress warning. It pops back to the program editor, refreshes it and closes the workout if the workout was on that day (`closeWorkoutAfterDelete`).
4. **The confirm dialog states the consequences.**
   - Day: "N exercises will be removed." (omitted for an empty day) and "Logged workouts stay in History.", plus the existing "Your workout in progress is on this day. Deleting ends it now; …".
   - Exercise: "Also deletes its N variants." (only when it has any) and "Logged workouts stay in History.", plus "Your workout in progress will drop this exercise; sets already logged are kept." when the running workout is on its day.
5. **Exercise delete during a workout on that day** is allowed. Afterwards:
   - Sets already logged stay. History, PRs and Stats are unaffected because sets are keyed by exercise, not by slot.
   - The slot leaves the live queue at once (`ActiveWorkoutController.dropDeletedSlots`). If the slot was current, the cursor moves to the next remaining slot that is neither skipped nor complete. If none is left after it, it moves to the first slot with sets left. If nothing is left, it goes to ALL DONE: the workout stays open and FINISH works — unless nothing was logged, in which case the workout is abandoned at once, as on resume (Live Activity ended, Home stops offering RESUME). Inserted exercises stay.
   - The slot's override row is kept as a *dropped* marker: `skipped = 1`, written when the slot had no override, in the delete's transaction. The queue ignores it, since it is built from the plan. The summary reads it, so it offers no ADD TO DAY / SAVE AS VARIANT for an exercise that ran only on the deleted slot. Such an exercise shows NOT IN PLAN with its sets. It is never attributed to another slot, including the swap-chain fallback when another slot was changed with "Change exercise".
   - The Live Activity is updated right away, and ends when nothing is left. The watch snapshot follows the state, so neither shows the deleted slot.
   - Resume abandons a session only when its queue is empty **and** nothing was logged.
6. All three entry points (row button, swipe, edit sheet DELETE) go through one helper in `program_delete.dart`: `confirmExerciseDelete` / `deleteExerciseConfirmed` / `deleteExerciseFlow`. Days use `confirmProgramDelete` / `deleteDayConfirmed` / `deleteDayFlow`.
7. Deleting the last day or the last exercise is allowed. The existing empty states show, and in the day editor EDIT mode RENAME DAY / DELETE DAY stay available.

## 3. Data & schema
**No schema change** (DB stays v9). The dropped marker is a normal `session_exercise_overrides` row. `program_exercise_id` has no FK.

## 4. Acceptance checks (QA runbook)
- **DEL-01** Program editor, not in EDIT: no red delete buttons; tapping a day opens it; swipe does nothing.
- **DEL-02** Program editor → EDIT: each day row shows a red remove button (VoiceOver "Delete <DAY>"); RENAME PROGRAM appears after the list; DONE hides both.
- **DEL-03** Tap a day's delete button → DELETE? dialog with "N exercises will be removed." and "Logged workouts stay in History." → CANCEL keeps the day; DELETE removes it and the count in the eyebrow updates.
- **DEL-04** EDIT mode, swipe a day row left → same dialog → DELETE removes it.
- **DEL-05** RENAME PROGRAM (EDIT mode) renames as EDIT used to.
- **DEL-06** Day editor, not in EDIT: no delete buttons, no RENAME DAY / DELETE DAY. EDIT → each exercise row shows the remove button; RENAME DAY and DELETE DAY appear after the last exercise.
- **DEL-07** Delete an exercise with variants → dialog says "Also deletes its N variants." → DELETE → the row is gone; reopening the day shows no orphan variants.
- **DEL-08** Delete an exercise without variants → no variants line; "Logged workouts stay in History." shown.
- **DEL-09** Tap an exercise (not EDIT) → edit sheet → DELETE → the same DELETE? dialog appears (it used to delete at once). CANCEL keeps it.
- **DEL-10** DELETE DAY → dialog with exercise count → DELETE → back on the program editor, the day is gone.
- **DEL-11** Delete every exercise of a day → empty state "Tap + EXERCISE to plan your first lift."; DELETE DAY still available. Delete every day → "Add a day like …" empty state.
- **DEL-12** Logged history: after DEL-07 / DEL-10 on a day with completed workouts, History still lists those workouts with all sets; Stats/PRs for the exercise unchanged.
- **DEL-13** Workout in progress on day D, current exercise X with 1 set logged. Programs → D → EDIT → delete X → the dialog shows "Your workout in progress will drop this exercise; sets already logged are kept." → DELETE → RESUME → the workout is on the next exercise; the X/N counter has one less; no crash.
- **DEL-14** Same, but delete a non-current exercise → the current exercise stays current; the deleted one is gone from the program status sheet.
- **DEL-15** Delete the workout's last remaining exercise(s) → RESUME shows ALL DONE; FINISH WORKOUT completes; summary lists the logged sets (NOT IN PLAN) and offers no ADD TO DAY for the deleted exercise; History shows the workout.
- **DEL-16** DEL-15, but kill the app before FINISH and relaunch → RESUME is offered (not abandoned); finish → sets in History.
- **DEL-17** Slot with a variant switched in (and a slot changed with "Change exercise"), 1 set logged → delete it → it leaves the workout; summary offers neither SAVE AS VARIANT nor ADD TO DAY for it.
- **DEL-18** Watch paired (if available) / Live Activity on: after DEL-13 the lock screen and the watch show the next exercise and the reduced total, never the deleted one.
- **DEL-19** Delete a day with the workout in progress on it (row button or DELETE DAY) → the existing "Your workout in progress is on this day. Deleting ends it now; …" warning → DELETE → the workout closes (Home no longer offers RESUME), sets in History.

## 5. Testing
- `test/delete_exercise_live_test.dart`: DAO (cascade, marker on a new/existing override, no marker without a workout, `hasActiveWorkoutOnSlot`); live drop (current → next, a completed next slot skipped, earlier deleted, current last → sets left, last remaining → open + finish, emptied with nothing logged → abandoned (an inserted one keeps it open), variant switched in, swapped slot, inserted kept, other day untouched, watch snapshot + Live Activity, resume ignores the marker, resume keeps a workout with sets, still abandons an empty one); summary (no ADD for a dropped exercise, inserted still ADD, no SAVE AS VARIANT, no swap-chain attribution to another swapped slot, `droppedSlotExerciseIds`).
- `test/delete_rows_widget_test.dart`: buttons absent outside EDIT and present in EDIT (44 pt, semantic tap action), dialog lines, cancel/confirm, a double tap opens one dialog (row button, DELETE DAY), the "1 DAY" eyebrow, day and exercise swipes, edit sheet DELETE confirms, DELETE DAY pops back and closes the workout, empty state after the last exercise.

## 6. Risks
| Risk | Likelihood | Mitigation |
|---|---|---|
| Users used EDIT as a one-tap rename | Med | Rename is one more tap (EDIT → RENAME). |
| Summary hides ADD TO DAY for an exercise the user deleted by mistake | Low | They can re-add it from the day editor. Sets are kept either way. |
