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
