import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart'
    show cursorAfter, insertOrderPosAfter;
import 'package:ls_workout_tracker/features/workout/application/workout_progress.dart';
import 'package:ls_workout_tracker/features/workout/domain/active_session.dart';
import 'package:ls_workout_tracker/features/workout/domain/workout_set.dart';

PlannedExercise _ex(
  String id, {
  int sets = 3,
  bool skipped = false,
  double position = 0,
}) =>
    PlannedExercise(
      programExerciseId: 'pe-$id',
      exerciseId: id,
      exerciseName: 'Ex $id',
      targetSets: sets,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 60,
      skipped: skipped,
      position: position,
    );

int _setSeq = 0;
WorkoutSet _set(
  String exerciseId, {
  int reps = 10,
  double weight = 60,
  String? id,
  String? setGroup,
  int groupSeq = 0,
}) =>
    WorkoutSet(
      id: id ?? 's-${_setSeq++}',
      sessionId: 'sess',
      exerciseId: exerciseId,
      setIndex: 0,
      reps: reps,
      weightKg: weight,
      rir: 0,
      loggedAt: DateTime.now(),
      setGroup: setGroup,
      groupSeq: groupSeq,
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

    test('skipped zero-logged exercise is not selected as active', () {
      // Ex a skipped (0/3), Ex b not started (0/3). Active should be b, not a.
      final q = [_ex('a', skipped: true), _ex('b')];
      final p = WorkoutProgress.from(_session(q));
      expect(p.activeIndex, 1);
      expect(p.exercise?.exerciseId, 'b');
    });

    test('skipped partially-logged exercise is bypassed', () {
      // Ex a skipped after 1/3 logged, Ex b not started. Active is b.
      final q = [_ex('a', skipped: true), _ex('b')];
      final p = WorkoutProgress.from(_session(q, sets: [_set('a')]));
      expect(p.activeIndex, 1);
      expect(p.exercise?.exerciseId, 'b');
    });

    test('only-remaining exercise skipped → allDone', () {
      // Ex a done, Ex b skipped → nothing left to do.
      final q = [_ex('a', sets: 1), _ex('b', skipped: true)];
      final p = WorkoutProgress.from(_session(q, sets: [_set('a')]));
      expect(p.allDone, true);
      expect(p.exercise, isNull);
    });
  });

  // The resume / watch-resync reconciliation. This is the durability guarantee
  // for "skip": a cursor-only nudge used to be overwritten here; now skipped
  // slots are walked past so the skip survives a relaunch.
  group('cursorAfter (resume reconciliation)', () {
    test('empty log → first exercise', () {
      final c = cursorAfter([_ex('a'), _ex('b')], const []);
      expect(c.exerciseIdx, 0);
      expect(c.setIdx, 0);
    });

    test('partial log → that exercise, setIdx = logged count', () {
      final c = cursorAfter([_ex('a'), _ex('b')], [_set('a'), _set('a')]);
      expect(c.exerciseIdx, 0);
      expect(c.setIdx, 2);
    });

    test('skipped first exercise is walked past even with 0 logged', () {
      final c = cursorAfter([_ex('a', skipped: true), _ex('b')], const []);
      expect(c.exerciseIdx, 1);
    });

    test('skip survives reconciliation: never snaps back to a skipped slot', () {
      // Ex a skipped with 1/3 logged (the historic corruption case), Ex b next.
      final c = cursorAfter(
        [_ex('a', skipped: true), _ex('b')],
        [_set('a')],
      );
      expect(c.exerciseIdx, 1);
    });

    test('all done or skipped → finished (cursor at queue length)', () {
      final c = cursorAfter(
        [_ex('a', sets: 1), _ex('b', skipped: true)],
        [_set('a')],
      );
      expect(c.exerciseIdx, 2);
    });
  });

  // Drop sets ride the general set-group primitive: a top+drops sharing one
  // set_group count as ONE completed set everywhere.
  group('set groups (drop sets)', () {
    // A drop set: top + 2 drops sharing group "g1".
    List<WorkoutSet> dropSet(String ex, String group) => [
          _set(ex, weight: 100, setGroup: group, groupSeq: 0),
          _set(ex, weight: 80, setGroup: group, groupSeq: 1),
          _set(ex, weight: 60, setGroup: group, groupSeq: 2),
        ];

    test('completedSetsFor counts distinct groups, not rows', () {
      // One drop set (3 rows) = 1 completed set.
      expect(completedSetsFor(dropSet('a', 'g1'), 'a'), 1);
      // Two drop sets = 2.
      final two = [...dropSet('a', 'g1'), ...dropSet('a', 'g2')];
      expect(completedSetsFor(two, 'a'), 2);
    });

    test('plain sets are singleton groups (count == rows)', () {
      expect(completedSetsFor([_set('a'), _set('a'), _set('a')], 'a'), 3);
    });

    test('groupedSetsFor groups + orders by groupSeq', () {
      final groups = groupedSetsFor(dropSet('a', 'g1'), 'a');
      expect(groups, hasLength(1));
      expect(groups.first.map((s) => s.weightKg).toList(), [100, 80, 60]);
    });

    test('cursorAfter: a single drop set completes a 1-set exercise', () {
      // Ex a: 1 drop set target, the drop set logged → done; cursor on b.
      final c = cursorAfter(
        [_ex('a', sets: 1), _ex('b')],
        dropSet('a', 'g1'),
      );
      expect(c.exerciseIdx, 1);
    });

    test('cursorAfter: 1 of 2 drop sets logged → still on the exercise', () {
      final c = cursorAfter(
        [_ex('a', sets: 2), _ex('b')],
        dropSet('a', 'g1'),
      );
      expect(c.exerciseIdx, 0);
      expect(c.setIdx, 1); // one group done
    });

    test('WorkoutProgress counts a drop set as one completed set', () {
      final q = [_ex('a', sets: 3)];
      final p = WorkoutProgress.from(_session(q, sets: dropSet('a', 'g1')));
      expect(p.completedSets, 1);
      expect(p.activeIndex, 0);
    });
  });

  // Placement of a session-inserted exercise: a fractional position that sorts
  // it immediately after the chosen slot.
  group('insertOrderPosAfter', () {
    final queue = [
      _ex('a', position: 0),
      _ex('b', position: 1),
      _ex('c', position: 2),
    ];

    test('between two slots → midpoint (sorts right after)', () {
      final pos = insertOrderPosAfter(queue, 0); // after a
      expect(pos, 0.5);
      expect(pos, greaterThan(queue[0].position));
      expect(pos, lessThan(queue[1].position));
    });

    test('after the last slot → last + 1', () {
      expect(insertOrderPosAfter(queue, 2), 3.0);
    });

    test('afterIndex past the end → last + 1', () {
      expect(insertOrderPosAfter(queue, 99), 3.0);
    });

    test('empty queue → 0', () {
      expect(insertOrderPosAfter(const [], 0), 0);
    });

    test('repeated inserts after the same slot keep subdividing', () {
      final first = insertOrderPosAfter(queue, 0); // 0.5
      final withFirst = [
        queue[0],
        _ex('x', position: first),
        ...queue.sublist(1),
      ]..sort((p, q) => p.position.compareTo(q.position));
      final second = insertOrderPosAfter(withFirst, 0); // between a(0) and x(0.5)
      expect(second, 0.25);
      expect(second, lessThan(first));
    });
  });
}
