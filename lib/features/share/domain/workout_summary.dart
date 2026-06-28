import '../../workout/application/pr_detector.dart';
import '../../workout/domain/workout_set.dart';

/// One per-exercise line on the share card / text block: the exercise's TOP set
/// for the session (heaviest weight; ties broken by most reps) plus whether the
/// session set a PR for that exercise.
class TopSetLine {
  const TopSetLine({
    required this.exercise,
    required this.reps,
    required this.weightKg,
    required this.isPr,
  });

  final String exercise;
  final int reps;
  final double weightKg;
  final bool isPr;
}

/// A headless, testable snapshot of a single completed workout — everything the
/// share text and the branded image card need, with no Flutter or DB
/// dependency. Build it with [WorkoutSummary.fromSession].
class WorkoutSummary {
  const WorkoutSummary({
    required this.programName,
    required this.dayName,
    required this.date,
    required this.duration,
    required this.exerciseCount,
    required this.tonnageKg,
    required this.prCount,
    required this.lines,
  });

  /// Program name (e.g. "PPL"), or null for an orphaned/ad-hoc session.
  final String? programName;

  /// Day name (e.g. "Push A"), or null when the day is gone.
  final String? dayName;

  /// When the session started — the card/text date.
  final DateTime date;

  /// Wall-clock duration of the session.
  final Duration duration;

  /// Number of distinct exercises performed.
  final int exerciseCount;

  /// Total tonnage in kg = Σ(weightKg × reps) over every logged set.
  final double tonnageKg;

  /// How many exercises set a PR (weight or reps) this session.
  final int prCount;

  /// Per-exercise top-set lines, in the order the exercises were first logged.
  final List<TopSetLine> lines;

  /// Build a summary from a completed session's [sets].
  ///
  /// - [exerciseNames] maps exerciseId → display name (falls back to a generic
  ///   label when absent).
  /// - [prs] is the per-exercise PR map (e.g. from [PrDetector.detect]); an
  ///   exercise counts as a PR when its entry [ExercisePR.isPr] is true.
  /// - Tonnage = Σ(weightKg × reps). Top set per exercise = heaviest weight,
  ///   ties broken by the most reps at that weight.
  /// - Exercise/line order follows the order each exercise was first logged.
  static WorkoutSummary fromSession({
    required DateTime date,
    required Duration duration,
    required List<WorkoutSet> sets,
    required Map<String, String> exerciseNames,
    required Map<String, ExercisePR> prs,
    String? programName,
    String? dayName,
  }) {
    // Preserve first-seen order so the card mirrors how the session unfolded.
    final order = <String>[];
    final byExercise = <String, List<WorkoutSet>>{};
    var tonnageKg = 0.0;
    for (final s in sets) {
      tonnageKg += s.weightKg * s.reps;
      final list = byExercise[s.exerciseId];
      if (list == null) {
        byExercise[s.exerciseId] = [s];
        order.add(s.exerciseId);
      } else {
        list.add(s);
      }
    }

    final lines = <TopSetLine>[];
    var prCount = 0;
    for (final id in order) {
      final list = byExercise[id]!;
      var topWeight = list.first.weightKg;
      for (final s in list) {
        if (s.weightKg > topWeight) topWeight = s.weightKg;
      }
      // Most reps among the sets at the heaviest weight (tie-break).
      var topReps = 0;
      for (final s in list) {
        if ((s.weightKg - topWeight).abs() < 1e-6 && s.reps > topReps) {
          topReps = s.reps;
        }
      }
      final isPr = prs[id]?.isPr ?? false;
      if (isPr) prCount += 1;
      lines.add(TopSetLine(
        exercise: exerciseNames[id] ?? 'Exercise',
        reps: topReps,
        weightKg: topWeight,
        isPr: isPr,
      ));
    }

    return WorkoutSummary(
      programName: programName,
      dayName: dayName,
      date: date,
      duration: duration,
      exerciseCount: order.length,
      tonnageKg: tonnageKg,
      prCount: prCount,
      lines: lines,
    );
  }
}
