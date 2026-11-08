import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../programs/application/programs_provider.dart';
import '../../programs/domain/program_exercise.dart';
import '../../programs/domain/program_exercise_variant.dart';
import '../domain/active_session.dart';
import '../domain/session_exercise_override.dart';
import '../domain/workout_session.dart';
import '../domain/workout_set.dart';
import '../data/workout_dao.dart';
import 'active_workout_controller.dart';
import 'pr_detector.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PROGRESSION
// ─────────────────────────────────────────────────────────────────────────────

/// How an exercise compares to the last time this program day was trained.
///
/// The aggregate bar at the top of the summary and the per-exercise rows lower
/// down BOTH read this one enum, computed once in [classifyProgress], so the
/// tally and the rows can never disagree with each other.
enum ProgressDelta { up, matched, down, fresh }

/// Compare this session's top set against the previous session's top set for
/// the same exercise: heavier wins; at equal weight, more reps at that weight
/// wins. [prevTopWeightKg] == null means the exercise has no previous data.
ProgressDelta classifyProgress({
  required double topWeightKg,
  required int topReps,
  required double? prevTopWeightKg,
  required int? prevTopReps,
}) {
  if (prevTopWeightKg == null) return ProgressDelta.fresh;
  final dWeight = topWeightKg - prevTopWeightKg;
  if (dWeight > 1e-6) return ProgressDelta.up;
  if (dWeight < -1e-6) return ProgressDelta.down;
  final dReps = topReps - (prevTopReps ?? 0);
  if (dReps > 0) return ProgressDelta.up;
  if (dReps < 0) return ProgressDelta.down;
  return ProgressDelta.matched;
}

// ─────────────────────────────────────────────────────────────────────────────
//  SESSION SUMMARY
// ─────────────────────────────────────────────────────────────────────────────

/// Everything the summary screen shows for one exercise, pre-computed. The
/// widget layer does formatting only — no folds, no comparisons, no lookups.
class ExerciseSummary {
  const ExerciseSummary({
    required this.exerciseId,
    required this.name,
    required this.setGroups,
    required this.topWeightKg,
    required this.topReps,
    required this.volumeKg,
    required this.prevTopWeightKg,
    required this.prevTopReps,
    required this.prevSetCount,
    required this.delta,
    required this.pr,
    required this.planPe,
    this.planVariant,
    this.variantSlotPe,
    this.variantOfName,
    this.substituteSlotPe,
    this.substituteSlotName,
  });

  final String exerciseId;
  final String name;

  /// Logical sets: a drop set's top + drops are one group.
  final List<List<WorkoutSet>> setGroups;
  final double topWeightKg;

  /// Best reps achieved at [topWeightKg] this session.
  final int topReps;
  final double volumeKg;

  final double? prevTopWeightKg;
  final int? prevTopReps;
  final int? prevSetCount;
  final ProgressDelta delta;

  final ExercisePR? pr;

  /// The day's program row for this exercise, or null when it was substituted
  /// in or added ad hoc and isn't part of the plan.
  final ProgramExercise? planPe;

  /// SOW-14: set when this exercise is a VARIANT of one of the day's slots
  /// (and not itself a slot's base). Its target is the variant's own weight;
  /// [variantSlotPe] is the slot (sets/reps), [variantOfName] its base name.
  final ProgramExerciseVariant? planVariant;
  final ProgramExercise? variantSlotPe;
  final String? variantOfName;

  /// SOW-14 / H3: set when this exercise was swapped into a slot with "Change
  /// exercise" this session and is neither a base nor a variant: the summary
  /// offers to save it as a variant of that slot.
  final ProgramExercise? substituteSlotPe;
  final String? substituteSlotName;

  int get setCount => setGroups.length;
  bool get isPr => pr != null && pr!.isPr;
  bool get isVariant => planVariant != null;
  bool get inPlan => planPe != null || planVariant != null;
}

/// The whole screen's data, derived once in the provider.
class SessionSummary {
  const SessionSummary({
    required this.session,
    required this.exercises,
    required this.totalVolumeKg,
    required this.setCount,
    required this.prevTotalVolumeKg,
    required this.prevSessionStartedAt,
    required this.dayName,
    required this.programName,
    required this.prCount,
    required this.isFirstEverSession,
  });

  final WorkoutSession session;
  final List<ExerciseSummary> exercises;
  final double totalVolumeKg;

  /// Logical set count (drop sets count once), matching the active screen.
  final int setCount;

  /// Total volume of the previous completed session on this same program day,
  /// or null when there wasn't one.
  final double? prevTotalVolumeKg;
  final DateTime? prevSessionStartedAt;

  final String? dayName;
  final String? programName;
  final int prCount;

  /// True when this is the user's first-ever completed session. On day one
  /// every lift is technically a weight PR, so PR surfaces are suppressed.
  final bool isFirstEverSession;

  String? get programDayId => session.programDayId;
  int get exerciseCount => exercises.length;
  bool get hasPrevSession => prevSessionStartedAt != null;

  /// Volume change vs the previous session on this day; null without one.
  double? get volumeDeltaKg => prevTotalVolumeKg == null
      ? null
      : totalVolumeKg - prevTotalVolumeKg!;

  /// Whole-percent change vs the previous session; null when there's no
  /// previous session or it had zero volume (no meaningful denominator).
  int? get volumeDeltaPercent {
    final prev = prevTotalVolumeKg;
    if (prev == null || prev <= 0) return null;
    return ((totalVolumeKg - prev) / prev * 100).round();
  }

  /// Whole days since the previous session on this day (0 == today).
  int? get daysSincePrev {
    final prev = prevSessionStartedAt;
    if (prev == null) return null;
    final a = DateTime(prev.year, prev.month, prev.day);
    final b = DateTime(
        session.startedAt.year, session.startedAt.month, session.startedAt.day);
    return b.difference(a).inDays;
  }

  int tallyOf(ProgressDelta d) =>
      exercises.where((e) => e.delta == d).length;

  /// Average wall-clock time per logical set. Null when nothing was logged.
  Duration? get pacePerSet => setCount == 0
      ? null
      : Duration(microseconds: session.duration.inMicroseconds ~/ setCount);
}

final sessionSummaryProvider =
    FutureProvider.family<SessionSummary?, String>((ref, sessionId) async {
  final dao = ref.watch(workoutDaoProvider);
  final session = await dao.findSession(sessionId);
  if (session == null) return null;

  final sets = await dao.setsForSession(sessionId);
  final programDao = ref.watch(programDaoProvider);

  // Exercise order follows the order sets were logged in.
  final orderedIds = <String>[];
  for (final s in sets) {
    if (!orderedIds.contains(s.exerciseId)) orderedIds.add(s.exerciseId);
  }

  final nameById = <String, String>{};
  for (final id in orderedIds) {
    final e = await programDao.findExercise(id);
    if (e != null) nameById[id] = e.name;
  }

  String? dayName;
  String? programName;
  // The day's current targets keyed by exerciseId. A missing key means the
  // exercise isn't in the plan (substituted or inserted mid-session).
  final planByExercise = <String, ProgramExercise>{};
  final slots = <ProgramExerciseView>[];
  var variantsBySlot = <String, List<ProgramExerciseVariantView>>{};
  if (session.programDayId != null) {
    final d = await programDao.findDay(session.programDayId!);
    dayName = d?.name;
    if (d != null) {
      final p = await programDao.findProgram(d.programId);
      programName = p?.name;
    }
    for (final v
        in await programDao.listProgramExercises(session.programDayId!)) {
      planByExercise[v.pe.exerciseId] = v.pe;
      slots.add(v);
    }
    variantsBySlot =
        await programDao.listVariantsForDay(session.programDayId!);
  }
  final attribution = attributeToSlots(
    exerciseIds: orderedIds,
    slots: slots,
    variantsBySlot: variantsBySlot,
    overrides: await dao.overridesForSession(sessionId),
  );

  // Previous completed session on this same day — drives every "vs last"
  // comparison on the screen, plus the headline volume delta.
  Map<String, List<WorkoutSet>>? prevByExercise;
  double? prevTotalVolumeKg;
  DateTime? prevStartedAt;
  if (session.programDayId != null) {
    final prev = await dao.previousCompletedSessionForDay(
      session.programDayId!,
      before: session.startedAt,
    );
    if (prev != null) {
      final prevSets = await dao.setsForSession(prev.id);
      prevStartedAt = prev.startedAt;
      prevTotalVolumeKg =
          prevSets.fold<double>(0, (a, s) => a + s.weightKg * s.reps);
      prevByExercise = <String, List<WorkoutSet>>{};
      for (final s in prevSets) {
        prevByExercise.putIfAbsent(s.exerciseId, () => []).add(s);
      }
    }
  }

  final prs = await ref.watch(prDetectorProvider).detect(sessionId);
  final everCount = await dao.completedSessionCount();
  final isFirstEver = everCount <= 1;

  double topWeightOf(List<WorkoutSet> list) =>
      list.fold<double>(0, (m, s) => s.weightKg > m ? s.weightKg : m);
  int topRepsAt(List<WorkoutSet> list, double weight) => list
      .where((s) => s.weightKg >= weight - 1e-6)
      .fold<int>(0, (m, s) => s.reps > m ? s.reps : m);

  final exercises = <ExerciseSummary>[];
  for (final id in orderedIds) {
    final mine = sets.where((s) => s.exerciseId == id).toList();
    final top = topWeightOf(mine);
    final topReps = topRepsAt(mine, top);

    final prevSets = prevByExercise?[id];
    final prevTop =
        (prevSets == null || prevSets.isEmpty) ? null : topWeightOf(prevSets);
    final prevReps =
        prevTop == null ? null : topRepsAt(prevSets!, prevTop);
    final prevCount = prevSets == null
        ? null
        : groupedSetsFor(prevSets, id).length;

    exercises.add(ExerciseSummary(
      exerciseId: id,
      name: nameById[id] ?? 'Exercise',
      setGroups: groupedSetsFor(sets, id),
      topWeightKg: top,
      topReps: topReps,
      volumeKg: mine.fold<double>(0, (a, s) => a + s.weightKg * s.reps),
      prevTopWeightKg: prevTop,
      prevTopReps: prevReps,
      prevSetCount: prevCount,
      // No previous SESSION at all is a different statement from "this session
      // existed but didn't include this lift" — but both render as `fresh`.
      delta: prevByExercise == null
          ? ProgressDelta.fresh
          : classifyProgress(
              topWeightKg: top,
              topReps: topReps,
              prevTopWeightKg: prevTop,
              prevTopReps: prevReps,
            ),
      pr: isFirstEver ? null : prs[id],
      planPe: planByExercise[id],
      planVariant: attribution[id]?.variant,
      variantSlotPe: attribution[id]?.variant == null
          ? null
          : attribution[id]?.slot.pe,
      variantOfName: attribution[id]?.variant == null
          ? null
          : attribution[id]?.slot.exerciseName,
      substituteSlotPe: attribution[id]?.variant == null
          ? attribution[id]?.slot.pe
          : null,
      substituteSlotName: attribution[id]?.variant == null
          ? attribution[id]?.slot.exerciseName
          : null,
    ));
  }

  return SessionSummary(
    session: session,
    exercises: exercises,
    totalVolumeKg: sets.fold<double>(0, (a, s) => a + s.weightKg * s.reps),
    setCount: exercises.fold<int>(0, (a, e) => a + e.setCount),
    prevTotalVolumeKg: prevTotalVolumeKg,
    prevSessionStartedAt: prevStartedAt,
    dayName: dayName,
    programName: programName,
    prCount: exercises.where((e) => e.isPr).length,
    isFirstEverSession: isFirstEver,
  );
});

/// Where a logged exercise that is NOT a slot's base belongs (SOW-14).
class SlotAttribution {
  const SlotAttribution({required this.slot, this.variant});
  final ProgramExerciseView slot;

  /// The slot's variant row for the exercise; null when the exercise was only
  /// swapped into [slot] ("Change exercise") and isn't a variant of it.
  final ProgramExerciseVariant? variant;
}

/// Attribute each logged exercise to a day slot. Priority: a slot's base
/// (absent from the result — the caller's plan lookup handles it) → this
/// session's override for a slot that holds it as a variant → the first slot
/// (in day order) holding it as a variant → a slot it was swapped into this
/// session (override row's exercise or previous exercise; inserted rows never
/// count — those exercises are "added", not swapped). Pure for tests.
Map<String, SlotAttribution> attributeToSlots({
  required List<String> exerciseIds,
  required List<ProgramExerciseView> slots,
  required Map<String, List<ProgramExerciseVariantView>> variantsBySlot,
  required List<SessionExerciseOverride> overrides,
}) {
  final bases = {for (final s in slots) s.pe.exerciseId};
  final slotById = {for (final s in slots) s.pe.id: s};
  ProgramExerciseVariant? variantOf(String slotId, String exerciseId) {
    for (final v in variantsBySlot[slotId] ?? const []) {
      if (v.variant.exerciseId == exerciseId) return v.variant;
    }
    return null;
  }

  final touching = [
    for (final o in overrides)
      if (!o.inserted && slotById.containsKey(o.programExerciseId)) o,
  ];
  final out = <String, SlotAttribution>{};
  for (final id in exerciseIds) {
    if (bases.contains(id)) continue;
    SlotAttribution? found;
    for (final o in touching) {
      if (o.exerciseId != id && o.previousExerciseId != id) continue;
      final v = variantOf(o.programExerciseId, id);
      if (v != null) {
        found = SlotAttribution(slot: slotById[o.programExerciseId]!, variant: v);
        break;
      }
    }
    if (found == null) {
      for (final s in slots) {
        final v = variantOf(s.pe.id, id);
        if (v != null) {
          found = SlotAttribution(slot: s, variant: v);
          break;
        }
      }
    }
    if (found == null) {
      for (final o in touching) {
        if (o.exerciseId == id || o.previousExerciseId == id) {
          found = SlotAttribution(slot: slotById[o.programExerciseId]!);
          break;
        }
      }
    }
    if (found != null) out[id] = found;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROGRAM UPDATES
// ─────────────────────────────────────────────────────────────────────────────

enum ProgramUpdateKind {
  /// The exercise is in the day's plan and today beat (or matched, on a PR)
  /// its target weight — bump `default_weight`.
  raise,

  /// The exercise isn't in the plan (inserted, or not attributable to a slot)
  /// — add it to the day.
  add,

  /// SOW-14: a variant beat its own target — bump the VARIANT's weight, never
  /// the base's.
  raiseVariant,

  /// SOW-14 / H3: swapped into a slot with "Change exercise" — save it as a
  /// variant of that slot.
  addVariant,
}

/// One proposed edit to the program template, derived from what was actually
/// lifted. [applied] is the user-facing state the summary screen renders.
class ProgramUpdate {
  const ProgramUpdate({
    required this.exerciseId,
    required this.exerciseName,
    required this.kind,
    required this.programDayId,
    required this.proposedTargetKg,
    required this.targetSets,
    required this.targetRepsMin,
    required this.targetRepsMax,
    this.planPe,
    this.applied = false,
    this.createdProgramExerciseId,
    this.programExerciseId,
    this.slotName,
    this.planVariant,
    this.createdVariantId,
  });

  final String exerciseId;
  final String exerciseName;
  final ProgramUpdateKind kind;
  final String programDayId;

  /// Today's top weight — what the target becomes.
  final double proposedTargetKg;

  /// Sets / rep range actually performed (used when creating an ADD row).
  final int targetSets;
  final int targetRepsMin;
  final int targetRepsMax;

  /// The plan row as it was BEFORE applying — kept verbatim so undo restores
  /// every field, not just the weight. Null for [ProgramUpdateKind.add].
  final ProgramExercise? planPe;

  final bool applied;

  /// Id of the row created by an ADD, so undo can delete exactly that row.
  final String? createdProgramExerciseId;

  /// Variant kinds: the slot the variant belongs to (or will), and its base
  /// exercise's name for "VARIANT OF X" / "SAVE AS VARIANT OF X".
  final String? programExerciseId;
  final String? slotName;

  /// [ProgramUpdateKind.raiseVariant]: the variant row as it was before
  /// applying, kept verbatim for undo.
  final ProgramExerciseVariant? planVariant;

  /// [ProgramUpdateKind.addVariant]: the variant row created, so undo deletes
  /// exactly that row.
  final String? createdVariantId;

  bool get isAddKind =>
      kind == ProgramUpdateKind.add || kind == ProgramUpdateKind.addVariant;
  bool get isVariantKind =>
      kind == ProgramUpdateKind.raiseVariant ||
      kind == ProgramUpdateKind.addVariant;

  double? get currentTargetKg =>
      planPe?.defaultWeightKg ?? planVariant?.defaultWeightKg;

  ProgramUpdate copyWith({
    bool? applied,
    String? createdProgramExerciseId,
    String? createdVariantId,
    bool clearCreated = false,
  }) =>
      ProgramUpdate(
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        kind: kind,
        programDayId: programDayId,
        proposedTargetKg: proposedTargetKg,
        targetSets: targetSets,
        targetRepsMin: targetRepsMin,
        targetRepsMax: targetRepsMax,
        planPe: planPe,
        applied: applied ?? this.applied,
        createdProgramExerciseId: clearCreated
            ? null
            : (createdProgramExerciseId ?? this.createdProgramExerciseId),
        programExerciseId: programExerciseId,
        slotName: slotName,
        planVariant: planVariant,
        createdVariantId:
            clearCreated ? null : (createdVariantId ?? this.createdVariantId),
      );
}

/// Owns the "apply this session's numbers to the program" list AND its applied
/// flags, for one session.
///
/// The applied flag deliberately does NOT live in widget `State`. The summary
/// screen is a lazily-built `ListView`: a card scrolled out of the viewport has
/// its element destroyed, so a `State`-held flag silently resets — which is
/// exactly the bug this replaces. Holding it here (a non-autoDispose family
/// keyed by session) makes it survive scroll recycling, expand/collapse, theme
/// and unit flips, and a rebuild of the summary data itself.
class ProgramUpdatesController extends AsyncNotifier<List<ProgramUpdate>> {
  ProgramUpdatesController(this.sessionId);
  final String sessionId;

  @override
  Future<List<ProgramUpdate>> build() async {
    // `read`, not `watch`, on purpose: applied flags record user actions, and a
    // refetch of the summary must never recompute them away.
    final s = await ref.read(sessionSummaryProvider(sessionId).future);
    final dayId = s?.programDayId;
    if (s == null || dayId == null) return const [];

    final out = <ProgramUpdate>[];
    for (final e in s.exercises) {
      var repsMin = e.topReps;
      var repsMax = e.topReps;
      for (final g in e.setGroups) {
        for (final set in g) {
          if (set.reps < repsMin) repsMin = set.reps;
          if (set.reps > repsMax) repsMax = set.reps;
        }
      }
      final isWeightPr = e.pr != null && e.pr!.kind == PrKind.weight;
      final variant = e.planVariant;
      if (variant != null) {
        // A variant is tracked on its own (H1): offer its target, never ADD.
        if (e.topWeightKg <= variant.defaultWeightKg + 1e-6 && !isWeightPr) {
          continue;
        }
        out.add(ProgramUpdate(
          exerciseId: e.exerciseId,
          exerciseName: e.name,
          kind: ProgramUpdateKind.raiseVariant,
          programDayId: dayId,
          proposedTargetKg: e.topWeightKg,
          targetSets: e.setCount,
          targetRepsMin: repsMin,
          targetRepsMax: repsMax,
          programExerciseId: variant.programExerciseId,
          slotName: e.variantOfName,
          planVariant: variant,
        ));
        continue;
      }
      final pe = e.planPe;
      final sub = e.substituteSlotPe;
      if (pe == null && sub != null) {
        out.add(ProgramUpdate(
          exerciseId: e.exerciseId,
          exerciseName: e.name,
          kind: ProgramUpdateKind.addVariant,
          programDayId: dayId,
          proposedTargetKg: e.topWeightKg,
          targetSets: e.setCount,
          targetRepsMin: repsMin,
          targetRepsMax: repsMax,
          programExerciseId: sub.id,
          slotName: e.substituteSlotName,
        ));
        continue;
      }
      if (pe == null) {
        out.add(ProgramUpdate(
          exerciseId: e.exerciseId,
          exerciseName: e.name,
          kind: ProgramUpdateKind.add,
          programDayId: dayId,
          proposedTargetKg: e.topWeightKg,
          targetSets: e.setCount,
          targetRepsMin: repsMin,
          targetRepsMax: repsMax,
        ));
        continue;
      }
      // Offer the in-plan bump when today beat the target, or when it was a
      // weight PR — a lifter expects to be able to lock a PR in even if their
      // planned target sits above it.
      final beatsTarget = e.topWeightKg > pe.defaultWeightKg + 1e-6;
      if (!beatsTarget && !isWeightPr) continue;
      out.add(ProgramUpdate(
        exerciseId: e.exerciseId,
        exerciseName: e.name,
        kind: ProgramUpdateKind.raise,
        programDayId: dayId,
        proposedTargetKg: e.topWeightKg,
        targetSets: e.setCount,
        targetRepsMin: repsMin,
        targetRepsMax: repsMax,
        planPe: pe,
      ));
    }
    return out;
  }

  List<ProgramUpdate> get _list => state.value ?? const [];

  /// The list, resolving `build()` first if it hasn't run yet. A caller can
  /// reach the notifier (`ref.read(...notifier)`) before anything has awaited
  /// the provider, in which case `state` is still `AsyncLoading` and `_list`
  /// is empty — mutating on that silently no-ops.
  Future<List<ProgramUpdate>> _resolved() async => state.value ?? await future;

  ProgramUpdate? updateFor(String exerciseId) {
    for (final u in _list) {
      if (u.exerciseId == exerciseId) return u;
    }
    return null;
  }

  int get pendingCount => _list.where((u) => !u.applied).length;
  int get appliedCount => _list.where((u) => u.applied).length;

  Future<void> applyOne(String exerciseId) async {
    final list = [...await _resolved()];
    final i = list.indexWhere((u) => u.exerciseId == exerciseId);
    if (i < 0 || list[i].applied) return;
    list[i] = await _apply(list[i]);
    state = AsyncData(list);
    _refreshDay();
  }

  Future<void> undoOne(String exerciseId) async {
    final list = [...await _resolved()];
    final i = list.indexWhere((u) => u.exerciseId == exerciseId);
    if (i < 0 || !list[i].applied) return;
    list[i] = await _undo(list[i]);
    state = AsyncData(list);
    _refreshDay();
  }

  /// Apply every not-yet-applied update. Returns how many were applied.
  Future<int> applyAll() async {
    final list = [...await _resolved()];
    var n = 0;
    for (var i = 0; i < list.length; i++) {
      if (list[i].applied) continue;
      list[i] = await _apply(list[i]);
      if (list[i].applied) n++;
    }
    if (n > 0) {
      state = AsyncData(list);
      _refreshDay();
    }
    return n;
  }

  /// Reverse every applied update. Returns how many were reversed.
  Future<int> undoAll() async {
    final list = [...await _resolved()];
    var n = 0;
    for (var i = 0; i < list.length; i++) {
      if (!list[i].applied) continue;
      list[i] = await _undo(list[i]);
      n++;
    }
    if (n > 0) {
      state = AsyncData(list);
      _refreshDay();
    }
    return n;
  }

  Future<ProgramUpdate> _apply(ProgramUpdate u) async {
    final dao = ref.read(programDaoProvider);
    switch (u.kind) {
      case ProgramUpdateKind.raise:
        await dao.updateProgramExercise(
          u.planPe!.copyWith(defaultWeightKg: u.proposedTargetKg),
        );
        return u.copyWith(applied: true);
      case ProgramUpdateKind.add:
        final created = await dao.addProgramExercise(
          programDayId: u.programDayId,
          exerciseName: u.exerciseName,
          targetSets: u.targetSets,
          targetRepsMin: u.targetRepsMin,
          targetRepsMax: u.targetRepsMax,
          defaultWeightKg: u.proposedTargetKg,
        );
        return u.copyWith(applied: true, createdProgramExerciseId: created.id);
      case ProgramUpdateKind.raiseVariant:
        await dao.updateVariant(
          u.planVariant!.copyWith(defaultWeightKg: u.proposedTargetKg),
        );
        return u.copyWith(applied: true);
      case ProgramUpdateKind.addVariant:
        try {
          final created = await dao.addVariant(
            programExerciseId: u.programExerciseId!,
            exerciseName: u.exerciseName,
            defaultWeightKg: u.proposedTargetKg,
          );
          return u.copyWith(applied: true, createdVariantId: created.id);
        } on VariantConflict {
          // Added by hand since (or the slot changed): nothing to do.
          return u;
        }
    }
  }

  Future<ProgramUpdate> _undo(ProgramUpdate u) async {
    final dao = ref.read(programDaoProvider);
    switch (u.kind) {
      case ProgramUpdateKind.raise:
        // Restore the whole row, not just the weight.
        await dao.updateProgramExercise(u.planPe!);
        return u.copyWith(applied: false);
      case ProgramUpdateKind.add:
        final id = u.createdProgramExerciseId;
        if (id != null) await dao.deleteProgramExercise(id);
        return u.copyWith(applied: false, clearCreated: true);
      case ProgramUpdateKind.raiseVariant:
        await dao.updateVariant(u.planVariant!);
        return u.copyWith(applied: false);
      case ProgramUpdateKind.addVariant:
        final id = u.createdVariantId;
        if (id != null) await dao.deleteVariant(id);
        return u.copyWith(applied: false, clearCreated: true);
    }
  }

  /// Drop the cached day-exercise list so the program editor reflects the
  /// add/raise without an app restart.
  void _refreshDay() {
    final list = _list;
    if (list.isEmpty) return;
    ref.invalidate(dayExercisesProvider(list.first.programDayId));
    ref.invalidate(dayVariantsProvider(list.first.programDayId));
    ref.invalidate(slotVariantsProvider);
  }
}

final programUpdatesProvider = AsyncNotifierProvider.family<
    ProgramUpdatesController, List<ProgramUpdate>, String>(
  ProgramUpdatesController.new,
);
