import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/dialogs.dart';
import '../../history/application/history_provider.dart';
import '../../home/application/home_provider.dart';
import '../../stats/application/stats_provider.dart';
import '../../workout/application/active_workout_controller.dart';
import '../application/programs_provider.dart';

/// Shown in the delete confirmation when the workout in progress runs on the
/// program/day being deleted (review #4 / QA RISK-05).
String deleteEndsWorkoutWarning(String what) =>
    'Your workout in progress is on this $what. Deleting ends it now; '
    'sets logged so far stay in History.';

/// SOW-15: what a delete takes with it, spelled out in the confirmation.
const deleteKeepsHistoryLine = 'Logged workouts stay in History.';

String deleteDayExercisesLine(int n) =>
    '$n ${n == 1 ? 'exercise' : 'exercises'} will be removed.';

String deleteExerciseVariantsLine(int n) =>
    'Also deletes its $n ${n == 1 ? 'variant' : 'variants'}.';

/// The first line of an exercise's delete confirmation: an exercise has
/// nothing "inside it" — what goes with it is spelled out below.
String deleteExerciseLine(String label) => 'This will delete "$label".';

/// Shown when the workout in progress runs on the exercise's day: unlike a
/// day delete, the workout keeps going without the exercise.
const deleteDropsExerciseWarning =
    'Your workout in progress will drop this exercise; sets already logged '
    'are kept.';

/// Shown instead when it is the workout's only exercise and nothing has been
/// logged: dropping it abandons the workout
/// ([ActiveWorkoutController.dropDeletedSlots]).
const deleteEndsEmptyWorkoutWarning =
    'Your workout in progress has nothing logged and will end.';

/// D-0017 review #4: one delete at a time per app (provider container). The
/// confirm reads the DB before its dialog shows, so a fast second tap — on
/// DELETE DAY, a row's button, a swipe — used to open a second dialog, and
/// confirming then popped the wrong route. While a delete is in flight (the
/// reads, the dialog and the delete itself) another one is ignored and
/// returns false.
final _deleteBusy = Expando<bool>('deleteBusy');

Future<bool> _guarded(
  ProviderContainer container,
  Future<bool> Function() body,
) async {
  if (_deleteBusy[container] ?? false) return false;
  _deleteBusy[container] = true;
  try {
    return await body();
  } finally {
    _deleteBusy[container] = null;
  }
}

/// Confirm deleting a program ([programId]) or a day ([dayId]), warning when
/// the running workout is on it. A day's dialog also says how many exercises
/// go with it. Returns false at once while another delete is in flight.
Future<bool> confirmProgramDelete(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  String? programId,
  String? dayId,
}) =>
    _guarded(
      ProviderScope.containerOf(context, listen: false),
      () => _confirmProgramDelete(
        context,
        ref,
        label: label,
        programId: programId,
        dayId: dayId,
      ),
    );

Future<bool> _confirmProgramDelete(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  String? programId,
  String? dayId,
}) async {
  final dao = ref.read(programDaoProvider);
  final active =
      await dao.hasActiveWorkout(programId: programId, dayId: dayId);
  final exercises = programId == null && dayId != null
      ? (await dao.listProgramExercises(dayId)).length
      : null;
  if (!context.mounted) return false;
  return await confirmDelete(
        context,
        label,
        details: [
          if (exercises != null && exercises > 0)
            deleteDayExercisesLine(exercises),
          if (exercises != null) deleteKeepsHistoryLine,
        ],
        warning: active
            ? deleteEndsWorkoutWarning(programId != null ? 'program' : 'day')
            : null,
      ) ??
      false;
}

/// Delete a day the user confirmed: the DAO delete (workouts kept and
/// detached), then close the running workout if it was on the day, and
/// refresh the program's day list. Takes the container, not a `WidgetRef`:
/// the tile or screen that asked is gone by the time this finishes.
Future<void> deleteDayConfirmed(
  ProviderContainer container, {
  required String programId,
  required String dayId,
}) async {
  await container.read(programDaoProvider).deleteDay(dayId);
  await closeWorkoutAfterDelete(container);
  container
    ..invalidate(programDaysProvider(programId))
    ..invalidate(dayExercisesProvider(dayId))
    ..invalidate(dayVariantsProvider(dayId));
}

/// Confirm, then delete the day. Returns whether it was deleted.
/// [onConfirmed] runs between the two (the day editor pops itself there).
/// A second call while one is in flight is ignored (returns false).
Future<bool> deleteDayFlow(
  BuildContext context,
  WidgetRef ref, {
  required String programId,
  required String dayId,
  required String label,
  VoidCallback? onConfirmed,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return _guarded(container, () async {
    final ok =
        await _confirmProgramDelete(context, ref, label: label, dayId: dayId);
    if (!ok) return false;
    onConfirmed?.call();
    await deleteDayConfirmed(container, programId: programId, dayId: dayId);
    return true;
  });
}

/// Confirm deleting one exercise (a program slot): how many variants go with
/// it, that History keeps its sets, and — when the running workout is on its
/// day — that the workout drops it. Returns false at once while another
/// delete is in flight.
Future<bool> confirmExerciseDelete(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  required String programExerciseId,
}) =>
    _guarded(
      ProviderScope.containerOf(context, listen: false),
      () => _confirmExerciseDelete(
        context,
        ref,
        label: label,
        programExerciseId: programExerciseId,
      ),
    );

Future<bool> _confirmExerciseDelete(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  required String programExerciseId,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final dao = ref.read(programDaoProvider);
  final variants = (await dao.listVariants(programExerciseId)).length;
  final active = await dao.hasActiveWorkoutOnSlot(programExerciseId);
  var ends = false;
  if (active) {
    // The workout may not be loaded yet (nothing has shown it this launch).
    await container.read(activeSessionProvider.future);
    ends = container
        .read(activeSessionProvider.notifier)
        .dropWouldEnd(programExerciseId);
  }
  if (!context.mounted) return false;
  return await confirmDelete(
        context,
        label,
        message: deleteExerciseLine(label),
        details: [
          if (variants > 0) deleteExerciseVariantsLine(variants),
          deleteKeepsHistoryLine,
        ],
        warning: !active
            ? null
            : ends
                ? deleteEndsEmptyWorkoutWarning
                : deleteDropsExerciseWarning,
      ) ??
      false;
}

/// Delete an exercise the user confirmed: the DAO delete (variants cascade;
/// the running workout's override is kept as a dropped marker), then drop the
/// slot from the running workout and refresh the day. Every exercise delete —
/// the row's button, the swipe and the edit sheet's DELETE — ends here.
Future<void> deleteExerciseConfirmed(
  ProviderContainer container, {
  required String programExerciseId,
  required String dayId,
}) async {
  await container
      .read(programDaoProvider)
      .deleteProgramExercise(programExerciseId);
  await container.read(activeSessionProvider.notifier).dropDeletedSlots();
  container
    ..invalidate(dayExercisesProvider(dayId))
    ..invalidate(dayVariantsProvider(dayId))
    ..invalidate(slotVariantsProvider(programExerciseId))
    ..invalidate(programExerciseProvider(programExerciseId));
}

/// Confirm, then delete the exercise. Returns whether it was deleted. A
/// second call while one is in flight is ignored (returns false).
Future<bool> deleteExerciseFlow(
  BuildContext context,
  WidgetRef ref, {
  required String programExerciseId,
  required String dayId,
  required String label,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return _guarded(container, () async {
    final ok = await _confirmExerciseDelete(
      context,
      ref,
      label: label,
      programExerciseId: programExerciseId,
    );
    if (!ok) return false;
    await deleteExerciseConfirmed(
      container,
      programExerciseId: programExerciseId,
      dayId: dayId,
    );
    return true;
  });
}

/// After the delete: close the running workout if it lost its day, so Home
/// stops offering RESUME, and refresh what aggregates completed sessions.
/// Takes the container, not a `WidgetRef`: the deleted tile is gone by the
/// time this finishes.
Future<void> closeWorkoutAfterDelete(ProviderContainer container) async {
  final closed = await container
      .read(activeSessionProvider.notifier)
      .closeIfDetached();
  if (!closed) return;
  container
    ..invalidate(lastSessionSummaryProvider)
    ..invalidate(historyListProvider)
    ..invalidate(loggedExercisesProvider)
    ..invalidate(exerciseProgressionProvider);
}
