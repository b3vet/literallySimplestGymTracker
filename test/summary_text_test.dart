import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart'
    show WeightUnit;
import 'package:ls_workout_tracker/features/share/application/summary_text.dart';
import 'package:ls_workout_tracker/features/share/domain/workout_summary.dart';

WorkoutSummary _summary({
  String? programName = 'PPL',
  String? dayName = 'Push Day',
  DateTime? date,
  Duration duration = const Duration(minutes: 47),
  int exerciseCount = 6,
  double tonnageKg = 12400,
  int prCount = 2,
  List<TopSetLine> lines = const [],
}) =>
    WorkoutSummary(
      programName: programName,
      dayName: dayName,
      date: date ?? DateTime(2026, 6, 23, 18, 30),
      duration: duration,
      exerciseCount: exerciseCount,
      tonnageKg: tonnageKg,
      prCount: prCount,
      lines: lines,
    );

void main() {
  group('buildSummaryText', () {
    test('exact text for a known summary (kg)', () {
      final s = _summary(
        lines: const [
          TopSetLine(
              exercise: 'Bench Press', reps: 5, weightKg: 100, isPr: true),
          TopSetLine(exercise: 'OHP', reps: 8, weightKg: 60, isPr: false),
          TopSetLine(
              exercise: 'Incline DB', reps: 10, weightKg: 30, isPr: true),
        ],
      );

      final text = buildSummaryText(s, WeightUnit.kg);

      // Name column padded to the longest name ("Bench Press" = 11), then two
      // spaces before the set value.
      const expected = 'LS · PUSH DAY — 23 Jun\n'
          '47 min · 6 exercises · 12,400 kg · 2 PRs\n'
          '\n'
          'Bench Press  100 kg × 5  (PR)\n'
          'OHP          60 kg × 8\n'
          'Incline DB   30 kg × 10  (PR)\n'
          '— logged with LS Gym Track';
      expect(text, expected);
    });

    test('PR markers appear only on PR lines', () {
      final s = _summary(
        prCount: 1,
        lines: const [
          TopSetLine(exercise: 'Squat', reps: 5, weightKg: 140, isPr: true),
          TopSetLine(exercise: 'Leg Curl', reps: 12, weightKg: 40, isPr: false),
        ],
      );
      final text = buildSummaryText(s, WeightUnit.kg);
      final squatLine =
          text.split('\n').firstWhere((l) => l.startsWith('Squat'));
      final curlLine =
          text.split('\n').firstWhere((l) => l.startsWith('Leg Curl'));
      expect(squatLine, contains('(PR)'));
      expect(curlLine, isNot(contains('(PR)')));
      // Singular PR label in the stats line.
      expect(text, contains('· 1 PR\n'));
    });

    test('lb unit converts weights and tonnage and labels them lb', () {
      final s = _summary(
        tonnageKg: 1000, // → 2205 lb
        prCount: 0,
        lines: const [
          // 100 kg → 220 lb (rounded).
          TopSetLine(exercise: 'Deadlift', reps: 3, weightKg: 100, isPr: false),
        ],
      );
      final text = buildSummaryText(s, WeightUnit.lb);
      expect(text, contains('2,205 lb'));
      expect(text, contains('Deadlift  220 lb × 3'));
      expect(text, isNot(contains('kg')));
    });

    test('zero PRs drops the PR clause from the stats line', () {
      final s = _summary(
        prCount: 0,
        exerciseCount: 1,
        lines: const [
          TopSetLine(exercise: 'Pull Up', reps: 8, weightKg: 0, isPr: false),
        ],
      );
      final text = buildSummaryText(s, WeightUnit.kg);
      final statsLine = text.split('\n')[1];
      expect(statsLine, isNot(contains('PR')));
      // Single exercise → singular noun.
      expect(statsLine, contains('1 exercise'));
      expect(statsLine, isNot(contains('exercises')));
    });

    test('header falls back to program name then "WORKOUT"', () {
      final noDay = _summary(dayName: null, programName: 'Upper');
      expect(buildSummaryText(noDay, WeightUnit.kg), startsWith('LS · UPPER —'));

      final orphan = _summary(dayName: null, programName: null);
      expect(
        buildSummaryText(orphan, WeightUnit.kg),
        startsWith('LS · WORKOUT —'),
      );
    });

    test('always ends with the attribution footer and no trailing newline', () {
      final s = _summary(
        lines: const [
          TopSetLine(exercise: 'Row', reps: 8, weightKg: 70, isPr: false),
        ],
      );
      final text = buildSummaryText(s, WeightUnit.kg);
      expect(text, endsWith('— logged with LS Gym Track'));
      expect(text.endsWith('\n'), isFalse);
    });

    test('a very long exercise name does not break the format', () {
      const longName = 'Bulgarian Split Squat (Rear-Foot Elevated)';
      final s = _summary(
        prCount: 0,
        lines: const [
          TopSetLine(exercise: longName, reps: 8, weightKg: 24, isPr: false),
          TopSetLine(exercise: 'Calf', reps: 15, weightKg: 80, isPr: false),
        ],
      );
      final text = buildSummaryText(s, WeightUnit.kg);
      // The full long name survives (no truncation in the text block) and its
      // set value still renders.
      expect(text, contains(longName));
      expect(text, contains('24 kg × 8'));
      expect(text, contains('80 kg × 15'));
      // No line is absurdly padded: the name column is capped at 20 chars, so a
      // short name like "Calf" is padded to 20, not to the 42-char long name.
      final calfLine = text.split('\n').firstWhere((l) => l.startsWith('Calf'));
      expect(calfLine.indexOf('80 kg'), lessThan(28));
    });

    test('tonnage thousands grouping handles small and large values', () {
      expect(
        buildSummaryText(_summary(tonnageKg: 950, prCount: 0), WeightUnit.kg),
        contains('950 kg'),
      );
      expect(
        buildSummaryText(
            _summary(tonnageKg: 1234567, prCount: 0), WeightUnit.kg),
        contains('1,234,567 kg'),
      );
    });

    test('empty session (no lines) still produces header, stats and footer', () {
      final s = _summary(exerciseCount: 0, prCount: 0, lines: const []);
      final text = buildSummaryText(s, WeightUnit.kg);
      final parts = text.split('\n');
      expect(parts.first, 'LS · PUSH DAY — 23 Jun');
      expect(parts[1], contains('0 exercises'));
      expect(text, endsWith('— logged with LS Gym Track'));
      // No blank-line/exercise block when there are no lines.
      expect(text, isNot(contains('\n\n')));
    });
  });
}
