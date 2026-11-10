import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/application/pr_detector.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

Future<Database> _openInMemory() => openTestDb();

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late WorkoutDao wDao;
  late ProgramDao pDao;
  late String dayId;
  late String exerciseId;
  var seq = 0;

  setUp(() async {
    seq = 0;
    db = await _openInMemory();
    wDao = WorkoutDao(db);
    pDao = ProgramDao(db);
    final program = await pDao.createProgram('P');
    final day = await pDao.createDay(program.id, 'Push');
    dayId = day.id;
    await pDao.addProgramExercise(
      programDayId: dayId,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 60,
    );
    exerciseId = (await pDao.listProgramExercises(dayId)).first.pe.exerciseId;
  });

  tearDown(() async => db.close());

  /// Log a completed session at an explicit [daysAgo]. PR detection and the
  /// "previous session" lookup both compare against `started_at`, and sessions
  /// created back-to-back in a test land in the same millisecond — so the
  /// timestamps are pinned rather than left to `DateTime.now()`.
  Future<String> logSession(double weightKg, {int reps = 5}) async {
    final at = DateTime(2026, 1, 1).add(Duration(days: seq++));
    final s = await wDao.startSession(dayId);
    await db.update(
      'workout_sessions',
      {
        'started_at': at.millisecondsSinceEpoch,
        'ended_at': at.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [s.id],
    );
    await wDao.insertSet(
      sessionId: s.id,
      exerciseId: exerciseId,
      setIndex: 0,
      reps: reps,
      weightKg: weightKg,
      rir: 0,
    );
    await db.update(
      'workout_sets',
      {'logged_at': at.millisecondsSinceEpoch},
      where: 'session_id = ?',
      whereArgs: [s.id],
    );
    await wDao.completeSession(s.id);
    return s.id;
  }

  test('deleting a session removes it and cascades to its sets', () async {
    final keep = await logSession(60);
    final drop = await logSession(80);

    expect((await wDao.listCompletedSessions()).length, 2);
    expect((await wDao.setsForSession(drop)).length, 1);

    await wDao.deleteSession(drop);

    expect(await wDao.findSession(drop), isNull);
    expect((await wDao.setsForSession(drop)), isEmpty,
        reason: 'sets must cascade with the session');
    // The other session is untouched.
    expect(await wDao.findSession(keep), isNotNull);
    expect((await wDao.setsForSession(keep)).length, 1);
    expect((await wDao.listCompletedSessions()).length, 1);
  });

  test('deleting the session that held a PR lowers the historical max', () async {
    await logSession(60);
    final prSession = await logSession(100);

    expect(await wDao.historicalMaxWeight(exerciseId, before: DateTime.now()),
        100);

    await wDao.deleteSession(prSession);

    expect(await wDao.historicalMaxWeight(exerciseId, before: DateTime.now()),
        60,
        reason: 'a deleted session must stop counting towards records');
  });

  test('a later session is re-detected as a PR once the heavier one is gone',
      () async {
    final first = await logSession(100);
    // Later, lighter session: not a PR while the 100kg session exists.
    final second = await logSession(80);

    var prs = await PrDetector(wDao).detect(second);
    expect(prs[exerciseId]?.isPr ?? false, isFalse);

    await wDao.deleteSession(first);

    prs = await PrDetector(wDao).detect(second);
    expect(prs[exerciseId]?.isPr, isTrue,
        reason: 'with the heavier session deleted, 80kg is now the best ever');
    expect(prs[exerciseId]?.kind, PrKind.weight);
  });

  test('deleting the previous session changes the "vs last time" baseline',
      () async {
    final older = await logSession(60);
    final middle = await logSession(70);
    final newest = await logSession(80);
    final newestSession = await wDao.findSession(newest);

    var prev = await wDao.previousCompletedSessionForDay(
      dayId,
      before: newestSession!.startedAt,
    );
    expect(prev?.id, middle);

    await wDao.deleteSession(middle);

    prev = await wDao.previousCompletedSessionForDay(
      dayId,
      before: newestSession.startedAt,
    );
    expect(prev?.id, older,
        reason: 'the comparison must fall back to the next surviving session');
  });

  test('deleting a session leaves the program untouched', () async {
    final s = await logSession(100);
    // Simulate the summary screen having raised the target from this session.
    final pe = (await pDao.listProgramExercises(dayId)).first.pe;
    await pDao.updateProgramExercise(pe.copyWith(defaultWeightKg: 100));

    await wDao.deleteSession(s);

    final after = (await pDao.listProgramExercises(dayId)).first.pe;
    expect(after.defaultWeightKg, 100,
        reason: 'applying a target is a separate edit; deleting the workout '
            'must not silently revert the program');
  });

  test('deleting a session also removes its mid-session substitutions',
      () async {
    final s = await wDao.startSession(dayId);
    final swapped = await pDao.findOrCreateExercise('Incline Press');
    await wDao.upsertOverride(
      sessionId: s.id,
      programExerciseId: (await pDao.listProgramExercises(dayId)).first.pe.id,
      exerciseId: swapped.id,
      previousExerciseId: exerciseId,
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 40,
    );
    await wDao.completeSession(s.id);
    expect((await wDao.overridesForSession(s.id)), isNotEmpty);

    await wDao.deleteSession(s.id);

    expect((await wDao.overridesForSession(s.id)), isEmpty,
        reason: 'overrides cascade with the session');
  });
}
