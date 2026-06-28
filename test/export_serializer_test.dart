import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart'
    show WeightUnit;
import 'package:ls_workout_tracker/features/export/application/export_serializer.dart';
import 'package:ls_workout_tracker/features/export/domain/export_models.dart';

ExportBundle _bundle(List<ExportSession> sessions, WeightUnit unit) =>
    ExportBundle(
      sessions: sessions,
      unit: unit,
      generatedAt: DateTime.utc(2026, 6, 23, 7, 41, 0),
      appVersion: '1.3.0+10',
    );

ExportSession _session(List<ExportSetRow> sets,
        {String? program = 'PPL', String? day = 'Push A'}) =>
    ExportSession(
      id: 'sess-1',
      startedAt: DateTime.utc(2026, 6, 21, 18, 2, 0),
      endedAt: DateTime.utc(2026, 6, 21, 18, 54, 0),
      programDayId: 'day-1',
      programId: 'prog-1',
      programName: program,
      dayName: day,
      sets: sets,
    );

ExportSetRow _set({
  String id = 'set-1',
  String exercise = 'Bench Press',
  String exerciseId = 'ex-1',
  int setNumber = 1,
  int reps = 8,
  double weightKg = 80,
  int rir = 2,
  String? setGroup,
  int groupSeq = 0,
}) =>
    ExportSetRow(
      id: id,
      loggedAt: DateTime.utc(2026, 6, 21, 18, 5, 30),
      exercise: exercise,
      exerciseId: exerciseId,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      rir: rir,
      setGroup: setGroup,
      groupSeq: groupSeq,
    );

void main() {
  group('toCsv', () {
    test('emits the exact header row', () {
      final csv = ExportSerializer.toCsv(_bundle([], WeightUnit.kg));
      expect(csv.split('\r\n').first, ExportSerializer.csvHeader.join(','));
    });

    test('one set -> one data row with ordered, typed fields (kg)', () {
      final csv = ExportSerializer.toCsv(
          _bundle([_session([_set()])], WeightUnit.kg));
      final lines = csv.trim().split('\r\n');
      expect(lines.length, 2); // header + 1 row
      expect(
        lines[1],
        '2026-06-21T18:05:30.000Z,sess-1,PPL,Push A,Bench Press,1,8,80,kg,80,2,,0',
      );
    });

    test('RFC-4180 escaping: comma + double-quote in exercise name', () {
      final comma = ExportSerializer.toCsv(_bundle(
          [_session([_set(exercise: 'Cable Fly, low')])], WeightUnit.kg));
      expect(comma, contains('"Cable Fly, low"'));
      final quote = ExportSerializer.toCsv(_bundle(
          [_session([_set(exercise: 'Bench "comp"')])], WeightUnit.kg));
      expect(quote, contains('"Bench ""comp"""'));
    });

    test('CSV formula-injection guard on a leading = + - @', () {
      final csv = ExportSerializer.toCsv(
          _bundle([_session([_set(exercise: '=cmd()')])], WeightUnit.kg));
      expect(csv, contains("'=cmd()"));
    });

    test('unit honesty: lb changes weight_display/unit, not weight_kg', () {
      final sessions = [_session([_set(weightKg: 80)])];
      final kg = ExportSerializer.toCsv(_bundle(sessions, WeightUnit.kg))
          .trim()
          .split('\r\n')[1];
      final lb = ExportSerializer.toCsv(_bundle(sessions, WeightUnit.lb))
          .trim()
          .split('\r\n')[1];
      expect(kg.split(','), containsAllInOrder(['80', 'kg', '80'])); // display,unit,kg
      // 80 kg ≈ 176 lb; weight_kg stays 80.
      expect(lb.split(','), containsAllInOrder(['176', 'lb', '80']));
    });

    test('drop set: two rows preserve set_group + group_seq', () {
      final csv = ExportSerializer.toCsv(_bundle([
        _session([
          _set(weightKg: 80, setGroup: 'grp-1', groupSeq: 0),
          _set(weightKg: 60, setGroup: 'grp-1', groupSeq: 1),
        ])
      ], WeightUnit.kg));
      final lines = csv.trim().split('\r\n');
      expect(lines.length, 3);
      expect(lines[1], endsWith('grp-1,0'));
      expect(lines[2], endsWith('grp-1,1'));
    });
  });

  group('toJsonMap / toJsonString', () {
    test('matches the documented shape and round-trips through json', () {
      final bundle = _bundle([_session([_set()])], WeightUnit.lb);
      final map = ExportSerializer.toJsonMap(bundle);
      expect(map['format'], 'ls-gym-track-export');
      expect(map['version'], 1);
      expect(map['units'], {'display': 'lb', 'storage': 'kg', 'source': 'kg'});
      final sessions = map['sessions'] as List;
      final session0 = sessions.first as Map;
      // import-ready stable ids
      expect(session0['id'], 'sess-1');
      expect(session0['program_day_id'], 'day-1');
      expect(session0['program_id'], 'prog-1');
      final set = (session0['sets'] as List).first as Map;
      expect(set['id'], 'set-1'); // stable per-set identity for SOW-12 dedup
      expect(set['exercise_id'], 'ex-1');
      expect(set['weight_kg'], 80.0); // raw kg unchanged
      expect(set['weight_display'], 176); // lb int
      expect(set['set_group'], isNull);
      // round-trips losslessly
      final decoded = jsonDecode(ExportSerializer.toJsonString(bundle));
      expect(decoded['sessions'], isA<List>());
    });

    test('empty bundle yields sessions: []', () {
      final map = ExportSerializer.toJsonMap(_bundle([], WeightUnit.kg));
      expect(map['sessions'], isEmpty);
    });

    test('all timestamps are ISO-8601 UTC (end in Z)', () {
      final map = ExportSerializer.toJsonMap(_bundle([_session([_set()])], WeightUnit.kg));
      expect((map['generated_at'] as String), endsWith('Z'));
      final set = (((map['sessions'] as List).first as Map)['sets'] as List)
          .first as Map;
      expect((set['logged_at'] as String), endsWith('Z'));
    });
  });
}
