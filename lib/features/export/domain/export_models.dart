import '../../../core/settings/settings_repository.dart' show WeightUnit;

/// Plain, serializer-friendly models for a full data export. No sqflite/widget
/// imports so the serializer is unit-testable headless. Weights are kg (storage
/// unit); display conversion happens in the serializer via `WeightConv`.
///
/// Stable ids (set `id`, `exerciseId`, `programDayId`, `programId`) are carried
/// so the JSON is **import-ready** — SOW-12 dedupes/round-trips by id, never by
/// fragile name/timestamp heuristics.

class ExportSetRow {
  const ExportSetRow({
    required this.id,
    required this.loggedAt,
    required this.exercise,
    required this.exerciseId,
    required this.setNumber,
    required this.reps,
    required this.weightKg,
    required this.rir,
    this.setGroup,
    required this.groupSeq,
  });

  final String id; // workout_sets.id — stable per-set identity (import dedup key)
  final DateTime loggedAt;
  final String exercise;
  final String exerciseId;
  final int setNumber; // workout_sets.set_index, as stored
  final int reps;
  final double weightKg; // raw storage value
  final int rir;
  final String? setGroup; // null for a singleton (plain set)
  final int groupSeq; // 0 for the top/plain set
}

class ExportSession {
  ExportSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.programDayId,
    this.programId,
    this.programName,
    this.dayName,
    List<ExportSetRow>? sets,
  }) : sets = sets ?? <ExportSetRow>[];

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? programDayId; // FK target for import reattachment
  final String? programId;
  final String? programName; // null if program orphaned/deleted
  final String? dayName;
  final List<ExportSetRow> sets;
}

/// Everything an export needs: the sessions plus the metadata that makes the
/// file self-describing and (crucially) re-import-ready (see SOW-12).
class ExportBundle {
  const ExportBundle({
    required this.sessions,
    required this.unit,
    required this.generatedAt,
    required this.appVersion,
  });

  final List<ExportSession> sessions;
  final WeightUnit unit; // display unit at export time
  final DateTime generatedAt;
  final String appVersion;
}
