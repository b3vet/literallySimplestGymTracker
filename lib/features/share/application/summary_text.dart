import '../../../core/settings/settings_repository.dart' show WeightUnit;
import '../../../core/util/weight.dart';
import '../domain/workout_summary.dart';

/// Builds the plain-text share block for a [WorkoutSummary] in the user's
/// [unit]. Pure — no Flutter, no IO — this is the unit-tested core.
///
/// Shape (kg user):
/// ```
/// LS · PUSH DAY — 23 Jun
/// 47 min · 6 exercises · 12,400 kg · 2 PRs
///
/// Bench Press   100 kg × 5  (PR)
/// OHP           60 kg × 8
/// …
/// — logged with LS Gym Track
/// ```
///
/// - The header day token falls back to the program name, then "WORKOUT".
/// - Stats line pluralises exercises/PRs and drops the PR clause when there are
///   none.
/// - Each line shows the exercise's top set via [WeightConv.format] (honoring
///   kg/lb), with a trailing "(PR)" marker when that exercise set a PR.
String buildSummaryText(WorkoutSummary s, WeightUnit unit) {
  final buf = StringBuffer();

  // ── Header: "LS · PUSH DAY — 23 Jun" ──────────────────────────────────────
  final dayToken = (s.dayName ?? s.programName ?? 'Workout').toUpperCase();
  buf.writeln('LS · $dayToken — ${summaryDateShort(s.date)}');

  // ── Stats: "47 min · 6 exercises · 12,400 kg · 2 PRs" ─────────────────────
  final parts = <String>[
    summaryDurationShort(s.duration),
    '${s.exerciseCount} ${_plural(s.exerciseCount, 'exercise', 'exercises')}',
    '${summaryTonnageGrouped(WeightConv.fromKg(s.tonnageKg, unit))} '
        '${unit.short}',
  ];
  if (s.prCount > 0) {
    parts.add('${s.prCount} ${_plural(s.prCount, 'PR', 'PRs')}');
  }
  buf.writeln(parts.join(' · '));

  // ── Per-exercise top sets ─────────────────────────────────────────────────
  if (s.lines.isNotEmpty) {
    buf.writeln();
    // Pad the exercise name to a common width so the set values align in a
    // monospace chat font, but cap the padding so a long name doesn't blow the
    // column out for every other line.
    var nameWidth = 0;
    for (final l in s.lines) {
      if (l.exercise.length > nameWidth) nameWidth = l.exercise.length;
    }
    if (nameWidth > 20) nameWidth = 20;
    for (final l in s.lines) {
      final name = l.exercise.padRight(nameWidth);
      final set = '${WeightConv.format(l.weightKg, unit)} × ${l.reps}';
      final pr = l.isPr ? '  (PR)' : '';
      buf.writeln('$name  $set$pr');
    }
  }

  // ── Attribution footer ────────────────────────────────────────────────────
  buf.write('— logged with LS Gym Track');
  return buf.toString();
}

/// "23 Jun" — day-of-month with a short month, no leading zero. Public so the
/// branded card reuses the exact same date formatting as the text block.
String summaryDateShort(DateTime d) => '${d.day} ${_months[d.month - 1]}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "47 min" or "1 h 12 min". Public so the branded card matches the text block.
String summaryDurationShort(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '$h h $m min';
  return '$m min';
}

String _plural(int n, String one, String many) => n == 1 ? one : many;

/// Integer value with grouped thousands ("12,400"). Rounds to whole units — the
/// share block is a glanceable headline, not a precise readout. Public so the
/// card reuses identical tonnage formatting.
String summaryTonnageGrouped(double value) {
  final n = value.round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return n < 0 ? '-$buf' : buf.toString();
}
