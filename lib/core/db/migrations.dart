import 'package:sqflite/sqflite.dart';

const schemaV1 = <String>[
  '''
  CREATE TABLE exercises (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE,
    notes TEXT
  )
  ''',
  '''
  CREATE TABLE programs (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE program_days (
    id TEXT PRIMARY KEY,
    program_id TEXT NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    position INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX idx_program_days_program ON program_days(program_id, position)',
  '''
  CREATE TABLE program_exercises (
    id TEXT PRIMARY KEY,
    program_day_id TEXT NOT NULL REFERENCES program_days(id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL REFERENCES exercises(id),
    position INTEGER NOT NULL,
    target_sets INTEGER NOT NULL,
    target_reps_min INTEGER NOT NULL,
    target_reps_max INTEGER NOT NULL,
    default_weight REAL NOT NULL
  )
  ''',
  'CREATE INDEX idx_pe_day ON program_exercises(program_day_id, position)',
  '''
  CREATE TABLE workout_sessions (
    id TEXT PRIMARY KEY,
    program_day_id TEXT REFERENCES program_days(id),
    started_at INTEGER NOT NULL,
    ended_at INTEGER,
    status TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_sessions_started ON workout_sessions(started_at DESC)',
  'CREATE INDEX idx_sessions_status  ON workout_sessions(status)',
  '''
  CREATE TABLE workout_sets (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL REFERENCES exercises(id),
    set_index INTEGER NOT NULL,
    reps INTEGER NOT NULL,
    weight REAL NOT NULL,
    rir INTEGER NOT NULL,
    logged_at INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX idx_sets_exercise_time ON workout_sets(exercise_id, logged_at DESC)',
  'CREATE INDEX idx_sets_session       ON workout_sets(session_id)',
];

/// v2: per-exercise weight step. NULL means "use the unit default".
const schemaV2Up = <String>[
  'ALTER TABLE program_exercises ADD COLUMN weight_step REAL',
];

/// v3: session-scoped exercise overrides. When a lifter swaps an exercise
/// mid-workout (e.g. "smith machine is occupied, do the plate-loaded
/// variant"), we persist the override here so it survives an app restart.
/// The override is keyed by (session_id, program_exercise_id) and only
/// applies to that one session — the program template stays untouched.
///
/// `previous_exercise_id` lets the active-workout screen show a
/// "PREVIOUS: N SETS ON [OLD NAME]" affordance for sets logged at this slot
/// before the swap. It is nullable because the very first swap of a slot
/// records its original planned exercise; subsequent swaps keep updating it
/// to whatever was in `exercise_id` immediately before the new swap.
const schemaV3Up = <String>[
  '''
  CREATE TABLE session_exercise_overrides (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    program_exercise_id TEXT NOT NULL,
    exercise_id TEXT NOT NULL REFERENCES exercises(id),
    previous_exercise_id TEXT REFERENCES exercises(id),
    target_sets INTEGER NOT NULL,
    target_reps_min INTEGER NOT NULL,
    target_reps_max INTEGER NOT NULL,
    default_weight REAL NOT NULL,
    weight_step REAL,
    UNIQUE (session_id, program_exercise_id)
  )
  ''',
  'CREATE INDEX idx_seo_session ON session_exercise_overrides(session_id)',
];

/// v4: durable "skip this exercise for this session" flag on the override row.
///
/// Skipping an exercise mid-workout used to be cursor-only (`goNext`), which
/// `cursorAfter` overwrites on resume/watch-resync — so the skip silently
/// evaporated. Persisting it here makes skip durable: `cursorAfter` walks past
/// any slot with `skipped = 1`, and the queue length stays invariant (the slot
/// is marked, never removed) so the watch's exercise index and the Live
/// Activity's total count remain valid.
///
/// A skip writes (or updates) the slot's override row carrying its current
/// exercise/targets; `previous_exercise_id` stays null for a skip that never
/// involved a swap, so the "SUBSTITUTED" badge never mis-fires.
const schemaV4Up = <String>[
  'ALTER TABLE session_exercise_overrides ADD COLUMN skipped INTEGER NOT NULL DEFAULT 0',
];

/// v5: session-only inserted exercises. A lifter can add an exercise to the
/// active session that isn't in the program day (e.g. they feel like doing it
/// today) — for that session only; the template stays untouched.
///
/// Rather than a separate table, an inserted exercise is an override row with
/// no template slot behind it: `inserted = 1` and a synthetic
/// `program_exercise_id` (which has no FK, so a free uuid is fine). `order_pos`
/// places it in the queue relative to the integer `position`s of the template
/// slots (a midpoint, so it can sit right after the current exercise). This
/// reuses every existing mutation path (add/remove-set, skip, change) — an
/// inserted slot is just another override.
const schemaV5Up = <String>[
  'ALTER TABLE session_exercise_overrides ADD COLUMN inserted INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE session_exercise_overrides ADD COLUMN order_pos REAL',
];

/// v6: drop sets, built on a general **set-group** primitive (so supersets
/// reuse it later with no refactor).
///
/// - `program_exercises.drop_count` / `session_exercise_overrides.drop_count`:
///   0 = normal exercise; N ≥ 1 = each working set is a drop set with N drops
///   after the top. Carried on the override too so the config survives a
///   mid-session swap / edit / insert.
/// - `workout_sets.set_group` + `group_seq`: a logged set's "back-to-back unit".
///   The effective group key is `set_group ?? id`, so a normal set is a
///   singleton group keyed by its own id (no backfill of existing rows). A drop
///   set's top + drops share one `set_group`, `group_seq` 0..N. Completed-set
///   count for an exercise = number of DISTINCT group keys among its rows
///   (identical to row-count for normal sets). Rest fires when a group
///   completes. Supersets later: one set per member shares a group.
const schemaV6Up = <String>[
  'ALTER TABLE program_exercises ADD COLUMN drop_count INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE session_exercise_overrides ADD COLUMN drop_count INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE workout_sets ADD COLUMN set_group TEXT',
  'ALTER TABLE workout_sets ADD COLUMN group_seq INTEGER NOT NULL DEFAULT 0',
];

/// v7 (SOW-14): exercise variants on a program slot. A slot keeps its base
/// exercise (`program_exercises.exercise_id`) and may hold 0..N variants —
/// ordinary `exercises` rows, each with its OWN target weight and step. No
/// backfill: existing slots simply have no variants.
///
/// The prescription columns (`target_sets` … `drop_count`) arrived in v8 (see
/// [schemaV8Up]); a fresh install gets them here, in the CREATE, so v8 is a
/// no-op on it. A v7 file from 1.5.0 (13) already has the table, so the
/// `IF NOT EXISTS` skips this statement and v8 adds the columns.
///
/// **Must stay idempotent.** sqflite has no downgrade hook here and silently
/// rewrites `user_version` when an older build (1.4.1, v6) opens this file, so
/// the next 1.5.0 launch runs this step again against a table that already
/// exists. Hence `IF NOT EXISTS` on both statements and no `ALTER TABLE`.
const schemaV7Up = <String>[
  '''
  CREATE TABLE IF NOT EXISTS program_exercise_variants (
    id TEXT PRIMARY KEY,
    program_exercise_id TEXT NOT NULL
      REFERENCES program_exercises(id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL REFERENCES exercises(id),
    position INTEGER NOT NULL,
    default_weight REAL NOT NULL,
    weight_step REAL,
    target_sets INTEGER,
    rep_min INTEGER,
    rep_max INTEGER,
    drop_count INTEGER,
    UNIQUE (program_exercise_id, exercise_id)
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_pev_pe '
      'ON program_exercise_variants(program_exercise_id, position)',
];

/// v8 (SOW-14, D-0016 / DEC-0007 #13): a variant carries its own prescription
/// — target sets, rep range and drop count — next to its weight and step.
/// All nullable: NULL means "inherit from the slot", so the variants written
/// by 1.5.0 (13) keep behaving exactly as before.
///
/// Column name → SQL type, in the order they are added.
const variantPrescriptionColumns = <String, String>{
  'target_sets': 'INTEGER',
  'rep_min': 'INTEGER',
  'rep_max': 'INTEGER',
  'drop_count': 'INTEGER',
};

/// Adds each [variantPrescriptionColumns] column that
/// `program_exercise_variants` lacks. **Idempotent by inspection**, not by
/// `IF NOT EXISTS` (SQLite has none for `ADD COLUMN`, and a second plain ALTER
/// fails): sqflite rewrites `user_version` when 1.4.1 (v6) or 1.5.0 (13, v7)
/// opens the file, so the next launch re-runs this step on a table that may
/// already have every column. A fresh install creates them in [schemaV7Up],
/// so this is a no-op there.
Future<void> schemaV8Up(DatabaseExecutor db) async {
  final have = {
    for (final c in await db.rawQuery(
      'PRAGMA table_info(program_exercise_variants)',
    ))
      c['name'] as String,
  };
  for (final e in variantPrescriptionColumns.entries) {
    if (have.contains(e.key)) continue;
    await db.execute(
      'ALTER TABLE program_exercise_variants ADD COLUMN ${e.key} ${e.value}',
    );
  }
}

/// v9 (SOW-14, D-0016 review #1): every exercise a slot has run in this
/// session, on its override row — a JSON array of exercise ids, oldest first.
/// The row itself only keeps the last two links (`exercise_id`,
/// `previous_exercise_id`), so a slot that ran Cable (a "Change exercise"),
/// then Machine, then the base again forgot the Cable sets: the carry-over
/// target, the switch-back rule, the PREVIOUSLY banner and the summary's slot
/// link all lost them. Workout sets carry no slot id, so this cannot be
/// derived from the sets alone. Nullable: NULL (rows written before v9, or by
/// an older build) means "nothing recorded beyond the two links".
const overrideRanExerciseIdsColumn = 'ran_exercise_ids';

/// Adds [overrideRanExerciseIdsColumn] to `session_exercise_overrides` when it
/// is missing. **Idempotent by inspection**, like [schemaV8Up]: an older build
/// (1.4.1, 13, or 14 at v8) stamps its own `user_version` on this file, so the
/// next launch re-runs this step on a table that already has the column.
Future<void> schemaV9Up(DatabaseExecutor db) async {
  final have = {
    for (final c in await db.rawQuery(
      'PRAGMA table_info(session_exercise_overrides)',
    ))
      c['name'] as String,
  };
  if (have.contains(overrideRanExerciseIdsColumn)) return;
  await db.execute(
    'ALTER TABLE session_exercise_overrides '
    'ADD COLUMN $overrideRanExerciseIdsColumn TEXT',
  );
}
