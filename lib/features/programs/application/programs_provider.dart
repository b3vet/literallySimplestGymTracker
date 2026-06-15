import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show databaseProvider;
import '../data/program_dao.dart';
import '../domain/program.dart';
import '../domain/program_day.dart';
import '../domain/program_exercise.dart';

final programDaoProvider = Provider<ProgramDao>((ref) {
  return ProgramDao(ref.watch(databaseProvider));
});

/// Set to a program id by the onboarding finale immediately before it routes
/// into the editor, so the editor can show a one-time "your program is ready"
/// coaching caption on first arrival and then clear it. Transient (in-memory)
/// by design — it only needs to survive the single navigation, not a relaunch.
class JustOnboardedProgramId extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final justOnboardedProgramIdProvider =
    NotifierProvider<JustOnboardedProgramId, String?>(
        JustOnboardedProgramId.new);

final programsListProvider = FutureProvider<List<Program>>((ref) {
  return ref.watch(programDaoProvider).listPrograms();
});

final programProvider =
    FutureProvider.family<Program?, String>((ref, id) async {
  return ref.watch(programDaoProvider).findProgram(id);
});

final programDaysProvider =
    FutureProvider.family<List<ProgramDay>, String>((ref, programId) {
  return ref.watch(programDaoProvider).listDays(programId);
});

final dayProvider =
    FutureProvider.family<ProgramDay?, String>((ref, id) async {
  return ref.watch(programDaoProvider).findDay(id);
});

final dayExercisesProvider =
    FutureProvider.family<List<ProgramExerciseView>, String>((ref, dayId) {
  return ref.watch(programDaoProvider).listProgramExercises(dayId);
});
