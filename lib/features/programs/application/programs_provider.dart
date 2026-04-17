import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show databaseProvider;
import '../data/program_dao.dart';
import '../domain/program.dart';
import '../domain/program_day.dart';
import '../domain/program_exercise.dart';

final programDaoProvider = Provider<ProgramDao>((ref) {
  return ProgramDao(ref.watch(databaseProvider));
});

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
