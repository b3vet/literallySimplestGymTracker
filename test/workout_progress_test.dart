import 'package:flutter_test/flutter_test.dart';
import 'package:literally_simplest_gym_tracker/features/workout/application/workout_progress.dart';
import 'package:literally_simplest_gym_tracker/features/workout/domain/active_session.dart';
import 'package:literally_simplest_gym_tracker/features/workout/domain/workout_set.dart';

PlannedExercise _ex(String id, {int sets = 3}) => PlannedExercise(
      programExerciseId: 'pe-$id',
      exerciseId: id,
      exerciseName: 'Ex $id',
      targetSets: sets,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 60,
    );

WorkoutSet _set(String exerciseId, {int reps = 10, double weight = 60}) =>
    WorkoutSet(
      id: 's-${DateTime.now().microsecondsSinceEpoch}',
      sessionId: 'sess',
      exerciseId: exerciseId,
      setIndex: 0,
      reps: reps,
      weightKg: weight,
      rir: 0,
      loggedAt: DateTime.now(),
    );

ActiveSession _session(
  List<PlannedExercise> queue, {
  List<WorkoutSet> sets = const [],
  int cursor = 0,
}) =>
    ActiveSession(
      sessionId: 'sess',
      programDayId: 'day',
      startedAt: DateTime.now(),
      queue: queue,
      cursor: Cursor(exerciseIdx: cursor, setIdx: 0),
      loggedSets: sets,
    );

void main() {
  group('WorkoutProgress.from', () {
    test('empty session → first exercise', () {
      final p = WorkoutProgress.from(_session([_ex('a'), _ex('b')]));
      expect(p.activeIndex, 0);
      expect(p.exercise?.exerciseId, 'a');
      expect(p.allDone, false);
    });

    test('all complete → allDone', () {
      final q = [_ex('a', sets: 1), _ex('b', sets: 1)];
      final p = WorkoutProgress.from(
        _session(q, sets: [_set('a'), _set('b')]),
      );
      expect(p.allDone, true);
      expect(p.exercise, isNull);
    });

    test('last partial wins over earlier zero-logged exercise', () {
      // Ex a: 1/3 (skipped working sets), Ex b: 2/3 (currently active),
      // Ex c: 0/3 (not started). User is on b.
      final q = [_ex('a'), _ex('b'), _ex('c')];
      final p = WorkoutProgress.from(_session(
        q,
        sets: [_set('a'), _set('b'), _set('b')],
      ));
      expect(p.activeIndex, 1);
      expect(p.exercise?.exerciseId, 'b');
      expect(p.setsForActive, hasLength(2));
    });

    test('only zero-logged exercises → first zero-logged', () {
      // Ex a: 3/3 done, Ex b: 0/3, Ex c: 0/3.
      final q = [_ex('a'), _ex('b'), _ex('c')];
      final p = WorkoutProgress.from(_session(
        q,
        sets: [_set('a'), _set('a'), _set('a')],
      ));
      expect(p.activeIndex, 1);
      expect(p.exercise?.exerciseId, 'b');
    });

    test('multiple partials → pick the LAST one', () {
      // Ex a partial, Ex b partial — the user is on b.
      final q = [_ex('a'), _ex('b'), _ex('c')];
      final p = WorkoutProgress.from(_session(
        q,
        sets: [_set('a'), _set('b')],
      ));
      expect(p.activeIndex, 1);
      expect(p.exercise?.exerciseId, 'b');
    });

    test('partials after a zero-logged still win', () {
      // Ex a: 3/3 done, Ex b: 0/3 (skipped intentionally), Ex c: 1/3 (on it).
      final q = [_ex('a'), _ex('b'), _ex('c')];
      final p = WorkoutProgress.from(_session(
        q,
        sets: [_set('a'), _set('a'), _set('a'), _set('c')],
      ));
      expect(p.activeIndex, 2);
      expect(p.exercise?.exerciseId, 'c');
    });

    test('UI cursor does not influence the active selection', () {
      // Cursor on a, but actual progress is partial on b.
      final q = [_ex('a'), _ex('b')];
      final p = WorkoutProgress.from(_session(
        q,
        sets: [_set('b')],
        cursor: 0,
      ));
      expect(p.activeIndex, 1);
      expect(p.exercise?.exerciseId, 'b');
    });
  });
}
