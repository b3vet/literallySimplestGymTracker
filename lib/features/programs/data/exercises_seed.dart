import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _seedAsset = 'assets/data/exercises_seed.json';

/// Loads the bundled list of common exercise names from
/// `assets/data/exercises_seed.json`. The list is cached for the lifetime of
/// the app via [seedExerciseNamesProvider].
Future<List<String>> loadSeedExerciseNames() async {
  final raw = await rootBundle.loadString(_seedAsset);
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final list = (decoded['exercises'] as List).cast<String>();
  return List.unmodifiable(list);
}

final seedExerciseNamesProvider = FutureProvider<List<String>>((ref) {
  return loadSeedExerciseNames();
});
