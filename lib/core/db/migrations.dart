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
