import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// Sibling positions of days, slots and variants. New rows get MAX + 1 (a
/// COUNT collided with an existing row once a delete left a gap); a delete
/// renumbers what is left 0..n-1; rows that already share a position (written
/// by the COUNT builds) still read in a stable, insertion order.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao dao;
  late String programId;
  late String dayId;

  setUp(() async {
    db = await openTestDb();
    dao = ProgramDao(db);
    programId = (await dao.createProgram('P')).id;
    dayId = (await dao.createDay(programId, 'Push')).id;
  });
  tearDown(() async => db.close());

  Future<String> addSlot(String name, [String? day]) async => (await dao
          .addProgramExercise(
            programDayId: day ?? dayId,
            exerciseName: name,
            targetSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 10,
            defaultWeightKg: 20,
          ))
      .id;

  Future<List<(String, int)>> slots([String? day]) async => [
        for (final v in await dao.listProgramExercises(day ?? dayId))
          (v.exerciseName, v.pe.position),
      ];

  Future<List<(String, int)>> days() async => [
        for (final d in await dao.listDays(programId)) (d.name, d.position),
      ];

  /// Raw row with a chosen position, as an older build could have left it.
  Future<void> rawSlot(String id, String name, int pos, [String? day]) async {
    final e = await dao.findOrCreateExercise(name);
    await db.insert('program_exercises', {
      'id': id,
      'program_day_id': day ?? dayId,
      'exercise_id': e.id,
      'position': pos,
      'target_sets': 3,
      'target_reps_min': 8,
      'target_reps_max': 10,
      'default_weight': 20.0,
    });
  }

  group('program exercises', () {
    test('+ EXERCISE after a middle delete appends at the end', () async {
      await addSlot('A');
      final b = await addSlot('B');
      await addSlot('C');
      await dao.deleteProgramExercise(b);
      await addSlot('D');
      expect(await slots(), [('A', 0), ('C', 1), ('D', 2)]);
    });

    test('a delete renumbers the rest 0..n-1, order kept', () async {
      final a = await addSlot('A');
      await addSlot('B');
      await addSlot('C');
      await addSlot('D');
      await dao.deleteProgramExercise(a);
      expect(await slots(), [('B', 0), ('C', 1), ('D', 2)]);
    });

    test('a delete on one day leaves another day alone', () async {
      final other = (await dao.createDay(programId, 'Pull')).id;
      await rawSlot('x1', 'Row', 3, other);
      await rawSlot('x2', 'Curl', 7, other);
      final a = await addSlot('A');
      await addSlot('B');
      await dao.deleteProgramExercise(a);
      expect(await slots(other), [('Row', 3), ('Curl', 7)]);
    });

    test('ADD TO DAY (summary) lands last after a delete', () async {
      // The summary's ADD TO DAY and its UNDO run addProgramExercise /
      // deleteProgramExercise — the same two calls as the editor.
      await addSlot('A');
      final b = await addSlot('B');
      await addSlot('C');
      await dao.deleteProgramExercise(b);
      final added = await addSlot('Cable Fly');
      expect((await slots()).last, ('Cable Fly', 2));
      await dao.deleteProgramExercise(added); // UNDO
      expect(await slots(), [('A', 0), ('C', 1)]);
    });

    test('duplicate positions read in a stable, insertion order', () async {
      // What QA saw: two exercises both at position 2.
      await rawSlot('s1', 'A', 0);
      await rawSlot('s2', 'B', 1);
      await rawSlot('s3', 'C', 2);
      await rawSlot('s4', 'D', 2);
      await rawSlot('s5', 'E', 1);
      final expected = [('A', 0), ('B', 1), ('E', 1), ('C', 2), ('D', 2)];
      for (var i = 0; i < 3; i++) {
        expect(await slots(), expected);
      }
    });

    test('a new slot after duplicates lands last; a delete heals them',
        () async {
      await rawSlot('s1', 'A', 0);
      await rawSlot('s2', 'B', 2);
      await rawSlot('s3', 'C', 2);
      await addSlot('D');
      expect(await slots(), [('A', 0), ('B', 2), ('C', 2), ('D', 3)]);
      await dao.deleteProgramExercise('s1');
      expect(await slots(), [('B', 0), ('C', 1), ('D', 2)]);
    });

    test('reorder writes 0..n-1 over gaps and duplicates', () async {
      await rawSlot('s1', 'A', 4);
      await rawSlot('s2', 'B', 4);
      await rawSlot('s3', 'C', 9);
      await dao.reorderProgramExercises(dayId, ['s3', 's1', 's2']);
      expect(await slots(), [('C', 0), ('A', 1), ('B', 2)]);
    });
  });

  group('days', () {
    test('+ DAY after a middle delete appends at the end', () async {
      final legs = await dao.createDay(programId, 'Legs');
      await dao.createDay(programId, 'Pull');
      await dao.deleteDay(legs.id);
      await dao.createDay(programId, 'Arms');
      expect(await days(), [('Push', 0), ('Pull', 1), ('Arms', 2)]);
    });

    test('a delete renumbers the rest 0..n-1, order kept', () async {
      await dao.createDay(programId, 'Pull');
      await dao.createDay(programId, 'Legs');
      await dao.deleteDay(dayId);
      expect(await days(), [('Pull', 0), ('Legs', 1)]);
    });

    test('duplicate positions read in a stable, insertion order', () async {
      Future<void> raw(String id, String name, int pos) => db.insert(
          'program_days',
          {'id': id, 'program_id': programId, 'name': name, 'position': pos});
      await raw('d2', 'Pull', 0);
      await raw('d3', 'Legs', 1);
      await raw('d4', 'Arms', 1);
      final expected = [('Push', 0), ('Pull', 0), ('Legs', 1), ('Arms', 1)];
      for (var i = 0; i < 3; i++) {
        expect(await days(), expected);
      }
      await dao.createDay(programId, 'Core');
      expect((await days()).last, ('Core', 2));
    });
  });

  group('variants', () {
    Future<String> variant(String slot, String name) async => (await dao
            .addVariant(
                programExerciseId: slot,
                exerciseName: name,
                defaultWeightKg: 10))
        .id;

    Future<List<(String, int)>> variants(String slot) async => [
          for (final v in await dao.listVariants(slot))
            (v.exerciseName, v.variant.position),
        ];

    test('a delete renumbers; a new one lands last', () async {
      final slot = await addSlot('Press');
      await variant(slot, 'V1');
      final v2 = await variant(slot, 'V2');
      await variant(slot, 'V3');
      await dao.deleteVariant(v2);
      expect(await variants(slot), [('V1', 0), ('V3', 1)]);
      await variant(slot, 'V4');
      expect(await variants(slot), [('V1', 0), ('V3', 1), ('V4', 2)]);
    });

    test('duplicate positions read in a stable, insertion order', () async {
      final slot = await addSlot('Press');
      for (final (i, name) in ['V1', 'V2', 'V3'].indexed) {
        final e = await dao.findOrCreateExercise(name);
        await db.insert('program_exercise_variants', {
          'id': 'v$i',
          'program_exercise_id': slot,
          'exercise_id': e.id,
          'position': i == 0 ? 1 : 0,
          'default_weight': 10.0,
        });
      }
      for (var i = 0; i < 3; i++) {
        expect(await variants(slot), [('V2', 0), ('V3', 0), ('V1', 1)]);
      }
    });
  });

  group('copy (SOW-13)', () {
    /// Source day with a gap and a duplicate, plus a variant on each slot.
    Future<void> messy() async {
      await rawSlot('s1', 'A', 1);
      await rawSlot('s2', 'B', 3);
      await rawSlot('s3', 'C', 3);
      await dao.addVariant(
          programExerciseId: 's2', exerciseName: 'B2', defaultWeightKg: 5);
    }

    test('duplicateDay copies in order, renumbered 0..n-1, lands last',
        () async {
      await dao.createDay(programId, 'Pull');
      final legs = await dao.createDay(programId, 'Legs');
      await dao.deleteDay(legs.id);
      await messy();
      final copy = await dao.duplicateDay(dayId, name: 'Push COPY');
      expect(await days(), [('Push', 0), ('Pull', 1), ('Push COPY', 2)]);
      expect(await slots(copy.id), [('A', 0), ('B', 1), ('C', 2)]);
      final copiedB = (await dao.listProgramExercises(copy.id))[1].pe.id;
      final v = await dao.listVariants(copiedB);
      expect([for (final x in v) (x.exerciseName, x.variant.position)],
          [('B2', 0)]);
    });

    test('duplicateProgram copies in order, renumbered 0..n-1', () async {
      await db.insert('program_days',
          {'id': 'dx', 'program_id': programId, 'name': 'Pull', 'position': 0});
      await db.insert('program_days',
          {'id': 'dy', 'program_id': programId, 'name': 'Legs', 'position': 5});
      await messy();
      final copy = await dao.duplicateProgram(programId, name: 'P COPY');
      final copied = await dao.listDays(copy.id);
      expect([for (final d in copied) (d.name, d.position)],
          [('Push', 0), ('Pull', 1), ('Legs', 2)]);
      expect(await slots(copied.first.id), [('A', 0), ('B', 1), ('C', 2)]);
    });
  });

  group('remapOrderPos (an inserted exercise in a running workout)', () {
    // The day had slots at 0,1,2,3; slot 1 was deleted: the rest were at
    // 0,2,3 and are now 0,1,2.
    const old = [0, 2, 3];
    test('keeps its place between the same neighbours', () {
      expect(remapOrderPos(-1, old), -1); // before the first
      expect(remapOrderPos(0.5, old), 0.25); // after 0, before (old) 2
      expect(remapOrderPos(1.5, old), 0.75); // after the deleted 1
      expect(remapOrderPos(2.5, old), 1.5);
      expect(remapOrderPos(4, old), 3); // after the last
    });
    test('is monotonic', () {
      final keys = <double>[-2, -0.5, 0, 0.5, 1, 1.5, 2, 2.25, 2.5, 3, 3.5, 9];
      final mapped = [for (final k in keys) remapOrderPos(k, old)];
      for (var i = 1; i < mapped.length; i++) {
        expect(mapped[i], greaterThanOrEqualTo(mapped[i - 1]));
      }
    });
    test('no slots left: unchanged', () => expect(remapOrderPos(1.5, []), 1.5));
  });
}
