import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart' show WeightUnit;
import '../data/export_dao.dart';
import '../domain/export_models.dart';
import 'export_serializer.dart';
import 'share_service.dart';

/// UI state for the export action.
sealed class ExportState {
  const ExportState();
}

class ExportIdle extends ExportState {
  const ExportIdle();
}

class ExportPreparing extends ExportState {
  const ExportPreparing();
}

class ExportError extends ExportState {
  const ExportError(this.message);
  final String message;
}

/// Gathers the full history, serializes CSV + JSON to temp files, and hands
/// them to the native share sheet. Off the build path; never blocks the UI.
class ExportController extends Notifier<ExportState> {
  @override
  ExportState build() => const ExportIdle();

  Future<void> exportAndShare() async {
    if (state is ExportPreparing) return; // ignore double-taps
    state = const ExportPreparing();
    try {
      final sessions = await ref.read(exportDaoProvider).exportAllSessions();
      final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
      final share = ref.read(shareServiceProvider);
      final version = await share.appVersion();
      final now = DateTime.now();

      final bundle = ExportBundle(
        sessions: sessions,
        unit: unit,
        generatedAt: now,
        appVersion: version,
      );

      final dir = await getTemporaryDirectory();
      // Clean up export files from PRIOR runs. We can't delete THIS run's files
      // right after sharing — the share sheet reads them when the user picks a
      // destination, which happens after shareFiles() returns — so we sweep the
      // previous run's leftovers here instead. Bounded: at most one run lingers.
      await _sweepPreviousExports(dir);

      final base = 'ls-gym-track-export-${DateFormat('yyyyMMdd-HHmmss').format(now)}';
      final csv = File('${dir.path}/$base.csv');
      final json = File('${dir.path}/$base.json');
      await csv.writeAsString(ExportSerializer.toCsv(bundle));
      await json.writeAsString(ExportSerializer.toJsonString(bundle));

      await share.shareFiles([csv.path, json.path]);
      state = const ExportIdle();
    } catch (e, st) {
      debugPrint('Export failed: $e\n$st');
      state = const ExportError('Export failed. Please try again.');
    }
  }

  Future<void> _sweepPreviousExports(Directory dir) async {
    try {
      await for (final e in dir.list()) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (e is File && name.startsWith('ls-gym-track-export-')) {
          await e.delete();
        }
      }
    } catch (_) {
      // Best-effort only; the OS reclaims the temp dir regardless.
    }
  }
}

final exportControllerProvider =
    NotifierProvider<ExportController, ExportState>(ExportController.new);
