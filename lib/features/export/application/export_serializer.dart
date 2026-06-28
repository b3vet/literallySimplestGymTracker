import 'dart:convert';

import '../../../core/settings/settings_repository.dart' show WeightUnit;
import '../../../core/util/weight.dart';
import '../domain/export_models.dart';

/// Pure, dependency-free serialization of an [ExportBundle] to CSV and JSON.
/// This is the load-bearing, unit-tested piece — it takes a fully-built bundle
/// and emits strings; no DB, no Flutter, no file IO.
class ExportSerializer {
  /// Schema version of the JSON export contract (see SOW-12 import consumer).
  static const int jsonSchemaVersion = 1;

  static const List<String> csvHeader = [
    'date',
    'session_id',
    'program',
    'day',
    'exercise',
    'set_number',
    'reps',
    'weight_display',
    'unit',
    'weight_kg',
    'rir',
    'set_group',
    'group_seq',
  ];

  /// One row per logged set across every session, RFC-4180-escaped, with a
  /// leading header row. Uses `\r\n` line endings (Excel-friendly).
  static String toCsv(ExportBundle b) {
    final sb = StringBuffer()..write(_row(csvHeader));
    for (final s in b.sessions) {
      for (final set in s.sets) {
        sb.write(_row([
          _iso(set.loggedAt),
          s.id,
          _guardText(s.programName ?? ''),
          _guardText(s.dayName ?? ''),
          _guardText(set.exercise),
          '${set.setNumber}',
          '${set.reps}',
          _displayWeightStr(set.weightKg, b.unit),
          b.unit.short,
          _kgStr(set.weightKg),
          '${set.rir}',
          set.setGroup ?? '',
          '${set.groupSeq}',
        ]));
      }
    }
    return sb.toString();
  }

  static Map<String, Object?> toJsonMap(ExportBundle b) => {
        'format': 'ls-gym-track-export',
        'version': jsonSchemaVersion,
        'generated_at': _iso(b.generatedAt),
        'app_version': b.appVersion,
        // `source: kg` tells a strict importer (SOW-12) that weight_kg is the
        // lossless source-of-truth and weight_display is derived/rounded.
        'units': {'display': b.unit.short, 'storage': 'kg', 'source': 'kg'},
        'sessions': [
          for (final s in b.sessions)
            {
              'id': s.id,
              'program_day_id': s.programDayId,
              'program_id': s.programId,
              'started_at': _iso(s.startedAt),
              'ended_at': s.endedAt == null ? null : _iso(s.endedAt!),
              'program': s.programName,
              'day': s.dayName,
              'sets': [
                for (final set in s.sets)
                  {
                    'id': set.id,
                    'logged_at': _iso(set.loggedAt),
                    'exercise': set.exercise,
                    'exercise_id': set.exerciseId,
                    'set_number': set.setNumber,
                    'reps': set.reps,
                    'weight_display': _displayWeightNum(set.weightKg, b.unit),
                    'weight_kg': set.weightKg,
                    'rir': set.rir,
                    'set_group': set.setGroup,
                    'group_seq': set.groupSeq,
                  }
              ],
            }
        ],
      };

  static String toJsonString(ExportBundle b) =>
      const JsonEncoder.withIndent('  ').convert(toJsonMap(b));

  // ── internals ──────────────────────────────────────────────────────────────

  static String _row(List<String> fields) =>
      '${fields.map(_escapeCsv).join(',')}\r\n';

  static String _escapeCsv(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Spreadsheet formula-injection guard for USER-TEXT fields only (program /
  /// day / exercise names). A leading `= + - @` can be interpreted as a formula
  /// in Excel/Sheets; a single-quote prefix forces text. Numeric columns
  /// (reps/weight/rir/group_seq) are app-controlled and never touched, so a
  /// value like a negative number can't be mangled.
  static String _guardText(String value) =>
      (value.isNotEmpty && '=+-@'.contains(value[0])) ? "'$value" : value;

  /// ISO-8601 in UTC, e.g. `2026-06-21T18:05:30.000Z`.
  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  /// Lossless raw kg string (`80`, `82.5`, `1.25`).
  static String _kgStr(double kg) =>
      kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toString();

  /// Display-unit weight as a string (kg keeps ≤1 decimal, lb rounds whole),
  /// mirroring `WeightConv.format`'s rules but without the unit suffix.
  static String _displayWeightStr(double kg, WeightUnit unit) {
    final v = WeightConv.fromKg(kg, unit);
    if (unit == WeightUnit.lb) return v.round().toString();
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  /// Display-unit weight as a JSON number (lb → int, kg → double).
  static num _displayWeightNum(double kg, WeightUnit unit) {
    final v = WeightConv.fromKg(kg, unit);
    return unit == WeightUnit.lb ? v.round() : v;
  }
}
