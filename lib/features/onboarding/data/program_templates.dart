// First-run starting-program templates.
//
// Three opinionated, gym-real defaults the onboarding wizard offers on its
// final step. Picking one seeds it into the database verbatim (see
// `ProgramDao.createProgramFromTemplate`) and drops the user straight into the
// program editor — so a brand-new install has a usable program in one tap.
//
// Exercise names are deliberately the SAME canonical strings as
// `assets/data/exercises_seed.json` (the editor's autocomplete source). That
// keeps the library consistent: an exercise the template creates is the exact
// row the user later finds when they type its name, so stats/autofill line up
// instead of fragmenting into near-duplicates.
//
// Weights are starting loads in **kilograms** (the DB's native unit — display
// converts per `WeightConv`). They're intentionally conservative; the whole
// point is the user edits these next. Tune freely — the *shape* (ordered days,
// ordered exercises, sets / rep-range / weight) is the contract the wizard
// cards render and the seeder stores.

/// One exercise slot inside a template day.
class TemplateExercise {
  const TemplateExercise(
    this.name,
    this.sets,
    this.repsMin,
    this.repsMax,
    this.weightKg,
  );

  /// Canonical exercise name — must match the seed library where an equivalent
  /// exists (e.g. "Bent-Over Row (Barbell)", not "Barbell Row").
  final String name;
  final int sets;
  final int repsMin;
  final int repsMax;

  /// Starting working weight in kilograms.
  final double weightKg;
}

/// One ordered training day (e.g. PUSH) and its ordered exercises.
class TemplateDay {
  const TemplateDay(this.name, this.exercises);
  final String name;
  final List<TemplateExercise> exercises;
}

/// A complete starting program offered on the onboarding template step.
class ProgramTemplate {
  const ProgramTemplate({
    required this.id,
    required this.name,
    required this.tagline,
    required this.days,
  });

  /// Stable key used for selection state in the wizard (never shown).
  final String id;

  /// Program name as seeded into the DB and shown on the card title.
  final String name;

  /// One short line of card sub-copy.
  final String tagline;

  final List<TemplateDay> days;

  int get dayCount => days.length;

  int get exerciseCount =>
      days.fold(0, (sum, d) => sum + d.exercises.length);

  int get totalSets => days.fold(
        0,
        (sum, d) => sum + d.exercises.fold(0, (s, e) => s + e.sets),
      );

  /// Ordered day names, e.g. `['PUSH', 'PULL', 'LEGS']`.
  List<String> get dayNames =>
      days.map((d) => d.name).toList(growable: false);

  /// The first day's first [count] exercise names — the card's "peek".
  List<String> exercisePeek([int count = 3]) =>
      days.first.exercises.take(count).map((e) => e.name).toList();

  /// How many more exercises the first day holds beyond the peek.
  int peekRemainder([int count = 3]) =>
      (days.first.exercises.length - count).clamp(0, 999);

  /// The most-used rep range across every exercise, formatted `min–max`.
  /// Reads cleaner on the card than the raw global span (which would surface
  /// outliers like a 4-rep deadlift next to a 20-rep calf raise).
  String get repBandLabel {
    final counts = <String, int>{};
    final firstSeen = <String, (int, int)>{};
    var order = 0;
    final rank = <String, int>{};
    for (final d in days) {
      for (final e in d.exercises) {
        final key = '${e.repsMin}-${e.repsMax}';
        counts[key] = (counts[key] ?? 0) + 1;
        if (!firstSeen.containsKey(key)) {
          firstSeen[key] = (e.repsMin, e.repsMax);
          rank[key] = order++;
        }
      }
    }
    if (counts.isEmpty) return '—';
    String best = counts.keys.first;
    for (final entry in counts.entries) {
      final isMore = entry.value > counts[best]!;
      final isTieEarlier =
          entry.value == counts[best]! && rank[entry.key]! < rank[best]!;
      if (isMore || isTieEarlier) best = entry.key;
    }
    final pair = firstSeen[best]!;
    return '${pair.$1}–${pair.$2}';
  }
}

/// The three templates, in display order.
const List<ProgramTemplate> kProgramTemplates = [
  _pushPull,
  _upperLower,
  _antagonist,
];

// ── PUSH PULL LEGS ──────────────────────────────────────────────────────────
// Listed by the product owner as "Push Pull Split"; seeded as the canonical
// 3-day Push / Pull / Legs rotation (a push/pull split without a legs day
// isn't a complete default anyone would train).
const _pushPull = ProgramTemplate(
  id: 'push_pull',
  name: 'Push Pull Legs',
  tagline: 'The proven 3-day rotation.',
  days: [
    TemplateDay('PUSH', [
      TemplateExercise('Bench Press', 4, 6, 10, 60),
      TemplateExercise('Overhead Press', 3, 8, 12, 35),
      TemplateExercise('Incline Dumbbell Press', 3, 8, 12, 22),
      TemplateExercise('Triceps Pushdown', 3, 10, 15, 25),
      TemplateExercise('Lateral Raise (Dumbbell)', 3, 12, 20, 8),
    ]),
    TemplateDay('PULL', [
      TemplateExercise('Conventional Deadlift', 3, 4, 6, 100),
      TemplateExercise('Bent-Over Row (Barbell)', 4, 6, 10, 60),
      TemplateExercise('Lat Pulldown', 3, 8, 12, 50),
      TemplateExercise('Face Pull', 3, 12, 20, 20),
      TemplateExercise('Barbell Curl', 3, 8, 12, 25),
    ]),
    TemplateDay('LEGS', [
      TemplateExercise('Back Squat', 4, 6, 10, 80),
      TemplateExercise('Romanian Deadlift', 3, 8, 12, 60),
      TemplateExercise('Leg Press', 3, 10, 15, 120),
      TemplateExercise('Leg Curl (Lying)', 3, 10, 15, 30),
      TemplateExercise('Calf Raise (Standing)', 4, 10, 15, 40),
    ]),
  ],
);

// ── UPPER LOWER ─────────────────────────────────────────────────────────────
const _upperLower = ProgramTemplate(
  id: 'upper_lower',
  name: 'Upper Lower',
  tagline: 'Four days, more frequency.',
  days: [
    TemplateDay('UPPER A', [
      TemplateExercise('Bench Press', 4, 6, 8, 60),
      TemplateExercise('Bent-Over Row (Barbell)', 4, 6, 8, 60),
      TemplateExercise('Overhead Press', 3, 8, 10, 35),
      TemplateExercise('Lat Pulldown', 3, 10, 12, 50),
      TemplateExercise('Triceps Pushdown', 3, 12, 15, 25),
    ]),
    TemplateDay('LOWER A', [
      TemplateExercise('Back Squat', 4, 6, 8, 80),
      TemplateExercise('Romanian Deadlift', 3, 8, 10, 60),
      TemplateExercise('Leg Press', 3, 10, 12, 120),
      TemplateExercise('Leg Curl (Lying)', 3, 12, 15, 30),
      TemplateExercise('Calf Raise (Standing)', 4, 10, 15, 40),
    ]),
    TemplateDay('UPPER B', [
      TemplateExercise('Incline Bench Press', 4, 8, 10, 45),
      TemplateExercise('Pull-Up', 4, 6, 10, 0),
      TemplateExercise('Seated Dumbbell Shoulder Press', 3, 10, 12, 18),
      TemplateExercise('Seated Cable Row', 3, 10, 12, 50),
      TemplateExercise('Barbell Curl', 3, 10, 12, 25),
    ]),
    TemplateDay('LOWER B', [
      TemplateExercise('Conventional Deadlift', 3, 4, 6, 100),
      TemplateExercise('Front Squat', 3, 8, 10, 50),
      TemplateExercise('Walking Lunge', 3, 10, 12, 20),
      TemplateExercise('Leg Extension', 3, 12, 15, 35),
      TemplateExercise('Calf Raise (Seated)', 4, 12, 15, 30),
    ]),
  ],
);

// ── ANTAGONIST ──────────────────────────────────────────────────────────────
// Pairs opposing muscle groups so push/pull alternate within a day.
const _antagonist = ProgramTemplate(
  id: 'antagonist',
  name: 'Antagonist',
  tagline: 'Pair opposing muscles.',
  days: [
    TemplateDay('CHEST / BACK', [
      TemplateExercise('Bench Press', 4, 6, 10, 60),
      TemplateExercise('Bent-Over Row (Barbell)', 4, 6, 10, 60),
      TemplateExercise('Incline Dumbbell Press', 3, 8, 12, 22),
      TemplateExercise('Lat Pulldown', 3, 8, 12, 50),
      TemplateExercise('Cable Chest Fly', 3, 12, 15, 15),
      TemplateExercise('Straight-Arm Pulldown', 3, 12, 15, 25),
    ]),
    TemplateDay('LEGS', [
      TemplateExercise('Back Squat', 4, 6, 10, 80),
      TemplateExercise('Leg Curl (Lying)', 4, 8, 12, 30),
      TemplateExercise('Leg Press', 3, 10, 15, 120),
      TemplateExercise('Leg Extension', 3, 12, 15, 35),
      TemplateExercise('Calf Raise (Standing)', 4, 12, 20, 40),
    ]),
    TemplateDay('ARMS / SHOULDERS', [
      TemplateExercise('Overhead Press', 4, 6, 10, 35),
      TemplateExercise('Barbell Curl', 4, 8, 12, 25),
      TemplateExercise('Triceps Pushdown', 4, 10, 15, 25),
      TemplateExercise('Hammer Curl', 3, 10, 12, 14),
      TemplateExercise('Lateral Raise (Dumbbell)', 4, 15, 20, 8),
    ]),
  ],
);
