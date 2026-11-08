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

/// Confirm deleting a program ([programId]) or a day ([dayId]), warning when
/// the running workout is on it.
Future<bool> confirmProgramDelete(
  BuildContext context,
  WidgetRef ref, {
  required String label,
  String? programId,
  String? dayId,
}) async {
  final active = await ref
      .read(programDaoProvider)
      .hasActiveWorkout(programId: programId, dayId: dayId);
  if (!context.mounted) return false;
  return await confirmDelete(
        context,
        label,
        warning: active
            ? deleteEndsWorkoutWarning(programId != null ? 'program' : 'day')
            : null,
      ) ??
      false;
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
