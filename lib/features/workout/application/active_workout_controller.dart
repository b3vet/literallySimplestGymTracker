import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart' show databaseProvider;
import '../../programs/application/programs_provider.dart';
import '../../programs/data/program_dao.dart';
import '../../programs/domain/program_exercise.dart';
import '../data/workout_dao.dart';
import '../domain/active_session.dart';
import '../domain/session_exercise_override.dart';
import '../domain/workout_set.dart';
import 'live_activity_controller.dart';
import 'pr_detector.dart';
import 'rest_timer_controller.dart';
import 'watch_bridge.g.dart';

/// Upper bound on per-exercise target sets for the in-workout add-set quick
/// action (the editor caps its picker at 10; a couple extra rows of headroom
/// cover drop-set / burnout scenarios). The floor is 1 — to drop the whole
/// exercise, skip it instead. Shared with the options sheet so the UI can
/// disable "Add set" at the cap without duplicating the number.
const int kMaxTargetSets = 12;

/// One sub-entry of a logged set group. A normal set is a single entry; a drop
/// set is the top entry (carries RIR) followed by its drops (RIR 0).
class SetEntry {
  const SetEntry({required this.reps, required this.weightKg, this.rir = 0});
  final int reps;
  final double weightKg;
  final int rir;
}

/// Given a queue and the sets already logged, return the cursor pointing at the
/// next unlogged set. Skipped slots are walked past (never the resting place of
/// the cursor) — this is what makes "skip" durable: it survives the
/// resume/watch-resync reconciliation rather than being a cursor-only nudge
/// that this routine would otherwise overwrite. Pure + top-level so the resume
/// reconciliation can be unit-tested directly.
Cursor cursorAfter(List<PlannedExercise> queue, List<WorkoutSet> loggedSets) {
  // Count DISTINCT group keys per exercise (a drop set's top+drops are one
  // group) — that's the number of logical sets completed.
  final groupsPerExercise = <String, Set<String>>{};
  for (final s in loggedSets) {
    (groupsPerExercise[s.exerciseId] ??= <String>{}).add(s.groupKey);
  }
  for (var i = 0; i < queue.length; i++) {
    final pe = queue[i];
    if (pe.skipped) continue;
    final logged = groupsPerExercise[pe.exerciseId]?.length ?? 0;
    if (logged < pe.targetSets) {
      return Cursor(exerciseIdx: i, setIdx: logged);
    }
  }
  return Cursor(exerciseIdx: queue.length, setIdx: 0);
}

/// Fractional queue `position` that places a newly inserted exercise
/// immediately after the slot at [afterIndex]: the midpoint to the next slot's
/// position, or `last + 1` when inserting after the end. Pure + top-level so
/// the placement logic is unit-testable.
double insertOrderPosAfter(List<PlannedExercise> queue, int afterIndex) {
  if (queue.isEmpty) return 0;
  if (afterIndex < 0) return queue.first.position - 1;
  if (afterIndex >= queue.length - 1) return queue.last.position + 1;
  final a = queue[afterIndex].position;
  final b = queue[afterIndex + 1].position;
  return (a + b) / 2;
}

final workoutDaoProvider = Provider<WorkoutDao>((ref) {
  return WorkoutDao(ref.watch(databaseProvider));
});

final prDetectorProvider = Provider((ref) {
  return PrDetector(ref.watch(workoutDaoProvider));
});

final sessionPrsProvider =
    FutureProvider.family<Map<String, ExercisePR>, String>(
        (ref, sessionId) async {
  return ref.watch(prDetectorProvider).detect(sessionId);
});

final activeSessionProvider =
    AsyncNotifierProvider<ActiveWorkoutController, ActiveSession?>(
  ActiveWorkoutController.new,
);

/// Last weight (in kg) logged for an exercise — used as SetLogSheet default.
final lastWeightForExerciseProvider =
    FutureProvider.family<double?, String>((ref, exerciseId) async {
  final last = await ref.read(workoutDaoProvider).lastSetForExercise(exerciseId);
  return last?.weightKg;
});

/// Display name for an exerciseId. Watched by the active workout screen to
/// render the "PREVIOUS: N SETS ON [OLD NAME]" affordance for slots that
/// have been substituted mid-session.
final exerciseNameProvider =
    FutureProvider.family<String?, String>((ref, exerciseId) async {
  final e = await ref.read(programDaoProvider).findExercise(exerciseId);
  return e?.name;
});

class ActiveWorkoutController extends AsyncNotifier<ActiveSession?> {
  WorkoutDao get _workoutDao => ref.read(workoutDaoProvider);
  ProgramDao get _programDao => ref.read(programDaoProvider);
  LiveActivityController get _liveActivity =>
      ref.read(liveActivityControllerProvider);
  bool get _liveActivityEnabled =>
      ref.read(settingsProvider).liveActivityEnabled;

  @override
  Future<ActiveSession?> build() async {
    return _resumeIfPossible();
  }

  DateTime? _currentRestEndsAt() {
    final rt = ref.read(restTimerProvider);
    return rt.endsAt != null && rt.endsAt!.isAfter(DateTime.now())
        ? rt.endsAt
        : null;
  }

  WeightUnit get _unit =>
      ref.read(settingsProvider).unit ?? WeightUnit.kg;

  LsAccentSpec get _accent =>
      lsAccentSpec(ref.read(settingsProvider).accent);

  void _pushLiveActivity(ActiveSession session) {
    if (!_liveActivityEnabled) return;
    _liveActivity.update(
      session: session,
      unit: _unit,
      accent: _accent,
      restEndsAt: _currentRestEndsAt(),
    );
  }

  Future<ActiveSession?> _resumeIfPossible() async {
    final session = await _workoutDao.findActiveSession();
    if (session == null || session.programDayId == null) return null;

    final planned = await _programDao.listProgramExercises(session.programDayId!);
    if (planned.isEmpty) {
      // Nothing to do — abandon.
      await _workoutDao.abandonSession(session.id);
      return null;
    }
    final overrides = await _workoutDao.overridesForSession(session.id);
    final queue = _buildQueue(planned, overrides);
    final loggedSets = await _workoutDao.setsForSession(session.id);
    final cursor = cursorAfter(queue, loggedSets);
    final resumed = ActiveSession(
      sessionId: session.id,
      programDayId: session.programDayId!,
      startedAt: session.startedAt,
      queue: queue,
      cursor: cursor,
      loggedSets: loggedSets,
    );
    if (_liveActivityEnabled) {
      _liveActivity.start(
        session: resumed,
        unit: _unit,
        accent: _accent,
        restEndsAt: _currentRestEndsAt(),
      );
    }
    return resumed;
  }

  /// Start a new session for the given program day. Fails if there's already an active session.
  Future<void> start(String programDayId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final existing = await _workoutDao.findActiveSession();
      if (existing != null) {
        throw StateError('A workout is already in progress.');
      }
      final planned = await _programDao.listProgramExercises(programDayId);
      if (planned.isEmpty) {
        throw StateError('This day has no exercises.');
      }
      final session = await _workoutDao.startSession(programDayId);
      final created = ActiveSession(
        sessionId: session.id,
        programDayId: programDayId,
        startedAt: session.startedAt,
        queue: planned.map(PlannedExercise.fromView).toList(),
        cursor: const Cursor(exerciseIdx: 0, setIdx: 0),
        loggedSets: const [],
      );
      if (_liveActivityEnabled) {
        await _liveActivity.start(
          session: created,
          unit: _unit,
          accent: _accent,
          restEndsAt: _currentRestEndsAt(),
        );
      }
      return created;
    });
  }

  Future<WorkoutSet?> logSet({
    required int reps,
    required double weightKg,
    required int rir,
  }) async {
    final current = state.value;
    if (current == null || current.isFinished) return null;
    final pe = current.currentExercise!;
    final newSet = await _workoutDao.insertSet(
      sessionId: current.sessionId,
      exerciseId: pe.exerciseId,
      setIndex: current.loggedSets.length,
      reps: reps,
      weightKg: weightKg,
      rir: rir,
    );

    final newLoggedSets = [...current.loggedSets, newSet];

    // Auto-advance only forward: if this set completes the target sets for
    // the current exercise, move the cursor to the next position. Never
    // rewind, so back-navigated edits don't drag the user away from where
    // they actually are.
    final setsForCurrent =
        newLoggedSets.where((s) => s.exerciseId == pe.exerciseId).length;
    final shouldAdvance = setsForCurrent >= pe.targetSets;
    final nextCursor = shouldAdvance
        ? Cursor(exerciseIdx: current.cursor.exerciseIdx + 1, setIdx: 0)
        : current.cursor;

    final updated = current.copyWith(
      loggedSets: newLoggedSets,
      cursor: nextCursor,
    );
    state = AsyncValue.data(updated);
    _pushLiveActivity(updated);
    return newSet;
  }

  /// Log a group of back-to-back entries as ONE logical set. A normal set is a
  /// single entry (singleton group, null `set_group`); a drop set is the top +
  /// its drops sharing one `set_group`, `group_seq` 0..N. Advances the cursor
  /// when the exercise's distinct-group count meets the target — and only after
  /// the WHOLE group lands (the UI collects all entries before calling this, so
  /// rest fires once, after the chain).
  Future<void> logSetGroup(List<SetEntry> entries) async {
    final current = state.value;
    if (current == null || current.isFinished || entries.isEmpty) return;
    final pe = current.currentExercise!;
    final groupId = entries.length > 1 ? const Uuid().v4() : null;
    var logged = current.loggedSets;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final newSet = await _workoutDao.insertSet(
        sessionId: current.sessionId,
        exerciseId: pe.exerciseId,
        setIndex: logged.length,
        reps: e.reps,
        weightKg: e.weightKg,
        rir: e.rir,
        setGroup: groupId,
        groupSeq: i,
      );
      logged = [...logged, newSet];
    }
    final groups = completedSetsFor(logged, pe.exerciseId);
    final shouldAdvance = groups >= pe.targetSets;
    final nextCursor = shouldAdvance
        ? Cursor(exerciseIdx: current.cursor.exerciseIdx + 1, setIdx: 0)
        : current.cursor;
    final updated = current.copyWith(loggedSets: logged, cursor: nextCursor);
    state = AsyncValue.data(updated);
    _pushLiveActivity(updated);
  }

  /// Delete a whole set group (a drop set's top+drops, or a single set) by its
  /// group key (`set_group ?? id`). The cursor is left where it is.
  Future<void> deleteSetGroup(String groupKey) async {
    final current = state.value;
    if (current == null) return;
    await _workoutDao.deleteSetGroup(groupKey);
    final updatedSets =
        current.loggedSets.where((s) => s.groupKey != groupKey).toList();
    final next = current.copyWith(loggedSets: updatedSets);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Replace an existing group's entries in place (edit a logged drop set):
  /// delete the old rows, insert the new ones at the same queue position
  /// without moving the cursor.
  Future<void> replaceSetGroup(String groupKey, List<SetEntry> entries) async {
    final current = state.value;
    if (current == null || entries.isEmpty) return;
    // Attribute to the exercise the old group belonged to (not necessarily the
    // cursor's current exercise — you can edit a past set).
    final old = current.loggedSets.where((s) => s.groupKey == groupKey).toList();
    if (old.isEmpty) return;
    final exerciseId = old.first.exerciseId;
    await _workoutDao.deleteSetGroup(groupKey);
    var logged =
        current.loggedSets.where((s) => s.groupKey != groupKey).toList();
    final groupId = entries.length > 1 ? const Uuid().v4() : null;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final newSet = await _workoutDao.insertSet(
        sessionId: current.sessionId,
        exerciseId: exerciseId,
        setIndex: logged.length,
        reps: e.reps,
        weightKg: e.weightKg,
        rir: e.rir,
        setGroup: groupId,
        groupSeq: i,
      );
      logged = [...logged, newSet];
    }
    final next = current.copyWith(loggedSets: logged);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Apply a set logged on the watch (SOW §6). The set log is append-only and
  /// keyed by [WatchSet.id]: if a set with this id already exists in
  /// [loggedSets] this is a no-op (idempotent — the watch may re-deliver or we
  /// may have already echoed it back), otherwise it's persisted under the
  /// watch-authored id and the cursor advances using the SAME rule as [logSet].
  ///
  /// Like [logSet], the set is attributed to the current exercise. Inbound
  /// apply only — it must not re-push a mutation back to the watch.
  Future<void> applyWatchLogSet(WatchSet set) async {
    final current = state.value;
    if (current == null || current.isFinished) return;
    // Idempotency: dedupe by id, never double-add the same set.
    if (current.loggedSets.any((s) => s.id == set.id)) return;
    // Attribute by the set's OWN exercise — a drop set's drops arrive after the
    // top may have advanced the cursor, so the cursor isn't a reliable owner.
    // Fall back to the cursor's exercise for older watch builds that omit it.
    final exerciseId = set.exerciseId.isNotEmpty
        ? set.exerciseId
        : (current.currentExercise?.exerciseId ?? '');
    if (exerciseId.isEmpty) return;
    final newSet = await _workoutDao.insertSet(
      id: set.id,
      sessionId: current.sessionId,
      exerciseId: exerciseId,
      setIndex: current.loggedSets.length,
      reps: set.reps,
      weightKg: set.weightKg,
      rir: set.rir,
      setGroup: set.setGroup,
      groupSeq: set.groupSeq,
    );

    final newLoggedSets = [...current.loggedSets, newSet];

    // Forward-only advance, group-aware: when the CURRENT cursor exercise has
    // met its target in DISTINCT groups (a drop set's top+drops count once),
    // move on. Drops attributed to an already-passed exercise don't re-advance.
    final pe = current.currentExercise;
    var nextCursor = current.cursor;
    if (pe != null &&
        completedSetsFor(newLoggedSets, pe.exerciseId) >= pe.targetSets) {
      nextCursor =
          Cursor(exerciseIdx: current.cursor.exerciseIdx + 1, setIdx: 0);
    }

    final updated = current.copyWith(
      loggedSets: newLoggedSets,
      cursor: nextCursor,
    );
    state = AsyncValue.data(updated);
    _pushLiveActivity(updated);
  }

  Future<void> editSet(WorkoutSet updated) async {
    final current = state.value;
    if (current == null) return;
    await _workoutDao.updateSet(updated);
    final updatedSets = [
      for (final s in current.loggedSets)
        if (s.id == updated.id) updated else s,
    ];
    final next = current.copyWith(loggedSets: updatedSets);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  Future<void> deleteSet(String setId) async {
    final current = state.value;
    if (current == null) return;
    await _workoutDao.deleteSet(setId);
    final updatedSets =
        current.loggedSets.where((s) => s.id != setId).toList();
    final next = current.copyWith(loggedSets: updatedSets);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Move the cursor to a specific exercise. Out-of-range values are clamped
  /// to a valid index (or to `queue.length` when [idx] is `>= queue.length`,
  /// which represents the "all exercises done" state).
  ///
  /// The cursor never rests on a skipped slot (skip is permanent): if [idx]
  /// points at one, fall forward to the next non-skipped slot, or the finished
  /// state if none remain. Guards the watch's `gotoExercise` mutation too.
  /// Cursor moves don't push to the Live Activity — the lock screen tracks
  /// the workout's actual progress, not what the user is looking at.
  Future<void> goToExerciseIndex(int idx) async {
    final current = state.value;
    if (current == null) return;
    var clamped = idx < 0
        ? 0
        : (idx > current.queue.length ? current.queue.length : idx);
    while (clamped < current.queue.length && current.queue[clamped].skipped) {
      clamped++;
    }
    final next = current.copyWith(
      cursor: Cursor(exerciseIdx: clamped, setIdx: 0),
    );
    state = AsyncValue.data(next);
  }

  /// First non-skipped slot strictly in [dir] (-1 prev / +1 next) from [from].
  /// Returns `queue.length` (finished) when stepping forward off the end, or
  /// `from` when there's nothing non-skipped behind.
  int _stepOverSkipped(ActiveSession s, int from, int dir) {
    var i = from + dir;
    while (i >= 0 && i < s.queue.length) {
      if (!s.queue[i].skipped) return i;
      i += dir;
    }
    return dir > 0 ? s.queue.length : from;
  }

  Future<void> goPrev() async {
    final current = state.value;
    if (current == null) return;
    return goToExerciseIndex(
        _stepOverSkipped(current, current.cursor.exerciseIdx, -1));
  }

  Future<void> goNext() async {
    final current = state.value;
    if (current == null) return;
    return goToExerciseIndex(
        _stepOverSkipped(current, current.cursor.exerciseIdx, 1));
  }

  /// Durably skip the current exercise for this session. Unlike the old
  /// cursor-only "next", this persists `skipped = 1` on the slot's override so
  /// it survives resume/watch-resync (the previous behaviour silently
  /// evaporated when `cursorAfter` snapped back). The slot stays in the queue
  /// (queue length is invariant → the watch index + Live Activity total stay
  /// valid); any logged sets are retained as honest history. Permanent in v1.
  /// The cursor is re-derived via [cursorAfter] so the live cursor and the
  /// resume cursor can never disagree.
  Future<void> skipCurrentExercise() async {
    final current = state.value;
    if (current == null) return;
    final idx = current.cursor.exerciseIdx;
    if (idx < 0 || idx >= current.queue.length) return;
    final slot = current.queue[idx];
    if (slot.skipped) return;
    await _workoutDao.upsertOverride(
      sessionId: current.sessionId,
      programExerciseId: slot.programExerciseId,
      exerciseId: slot.exerciseId,
      // Preserve the swap lineage (null for a slot never swapped) so the
      // "SUBSTITUTED / PREVIOUS SETS" affordance never mis-fires on a skip.
      previousExerciseId: slot.previousExerciseId,
      targetSets: slot.targetSets,
      targetRepsMin: slot.targetRepsMin,
      targetRepsMax: slot.targetRepsMax,
      defaultWeightKg: slot.defaultWeightKg,
      weightStepKg: slot.weightStepKg,
      skipped: true,
      inserted: slot.isInserted,
      orderPos: slot.isInserted ? slot.position : null,
      dropCount: slot.dropCount,
    );
    final skipped = slot.copyWith(skipped: true, isOverridden: true);
    final newQueue = [...current.queue]..[idx] = skipped;
    final cursor = cursorAfter(newQueue, current.loggedSets);
    final next = current.copyWith(queue: newQueue, cursor: cursor);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Add one target set to the current exercise (quick action). Persisted as a
  /// session override so it survives resume. The cursor stays put — the extra
  /// pending set row renders automatically off `targetSets`.
  Future<void> addSetToCurrent() async {
    final current = state.value;
    if (current == null) return;
    final idx = current.cursor.exerciseIdx;
    if (idx < 0 || idx >= current.queue.length) return;
    final slot = current.queue[idx];
    if (slot.targetSets >= kMaxTargetSets) return;
    await _writeSlotTargetSets(current, idx, slot, slot.targetSets + 1);
  }

  /// Remove the last target set from the current exercise (quick action).
  /// Floors at 1 set (to drop the whole exercise, use [skipCurrentExercise]).
  /// If the slot being dropped was already logged, that logged set is deleted
  /// too so the logged count never exceeds the (smaller) target. Persisted as
  /// a session override; the cursor stays put.
  Future<void> removeSetFromCurrent() async {
    final current = state.value;
    if (current == null) return;
    final idx = current.cursor.exerciseIdx;
    if (idx < 0 || idx >= current.queue.length) return;
    final slot = current.queue[idx];
    if (slot.targetSets <= 1) return;

    final loggedForCurrent = current.loggedSets
        .where((s) => s.exerciseId == slot.exerciseId)
        .toList();
    List<WorkoutSet>? newLoggedSets;
    if (loggedForCurrent.length >= slot.targetSets) {
      // The last slot is logged — remove that logged set as well.
      final removed = loggedForCurrent.last;
      await _workoutDao.deleteSet(removed.id);
      newLoggedSets =
          current.loggedSets.where((s) => s.id != removed.id).toList();
    }
    await _writeSlotTargetSets(
      current,
      idx,
      slot,
      slot.targetSets - 1,
      loggedSets: newLoggedSets,
    );
  }

  /// True when "remove set" on the current exercise will delete an already
  /// logged set (so the UI can confirm first). False when it just trims a
  /// pending target slot, or when removal is disallowed (targetSets <= 1).
  bool removeSetWouldDeleteLogged() {
    final current = state.value;
    if (current == null) return false;
    final idx = current.cursor.exerciseIdx;
    if (idx < 0 || idx >= current.queue.length) return false;
    final slot = current.queue[idx];
    if (slot.targetSets <= 1) return false;
    final logged = current.loggedSets
        .where((s) => s.exerciseId == slot.exerciseId)
        .length;
    return logged >= slot.targetSets;
  }

  /// Persist a target-set-count change to a slot's session override, preserving
  /// the slot's exercise / swap lineage / skip flag, and update the in-memory
  /// queue. The cursor is intentionally left where it is (add/remove-set adjust
  /// volume; they don't navigate). Optionally replaces [loggedSets].
  Future<void> _writeSlotTargetSets(
    ActiveSession current,
    int idx,
    PlannedExercise slot,
    int targetSets, {
    List<WorkoutSet>? loggedSets,
  }) async {
    await _workoutDao.upsertOverride(
      sessionId: current.sessionId,
      programExerciseId: slot.programExerciseId,
      exerciseId: slot.exerciseId,
      previousExerciseId: slot.previousExerciseId,
      targetSets: targetSets,
      targetRepsMin: slot.targetRepsMin,
      targetRepsMax: slot.targetRepsMax,
      defaultWeightKg: slot.defaultWeightKg,
      weightStepKg: slot.weightStepKg,
      skipped: slot.skipped,
      inserted: slot.isInserted,
      orderPos: slot.isInserted ? slot.position : null,
      dropCount: slot.dropCount,
    );
    final replaced = slot.copyWith(targetSets: targetSets, isOverridden: true);
    final newQueue = [...current.queue]..[idx] = replaced;
    final next = current.copyWith(
      queue: newQueue,
      loggedSets: loggedSets ?? current.loggedSets,
    );
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Insert a session-only exercise right after the current one. The program
  /// template is never touched — it's persisted as an `inserted` override row
  /// (so it survives resume and supports every other mutation) at a fractional
  /// `position` between the current slot and the next. The cursor stays put;
  /// once the current exercise completes, the reconciliation lands on the
  /// inserted one next. Growing the queue is safe for the watch + Live Activity
  /// (a fresh snapshot is pushed and the watch reconciles a longer queue).
  Future<void> insertExercise({
    required String name,
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required double defaultWeightKg,
    double? weightStepKg,
    int dropCount = 0,
  }) async {
    final current = state.value;
    if (current == null) return;
    final orderPos =
        insertOrderPosAfter(current.queue, current.cursor.exerciseIdx);
    final exercise = await _programDao.findOrCreateExercise(name);
    final programExerciseId = await _workoutDao.insertSessionExercise(
      sessionId: current.sessionId,
      exerciseId: exercise.id,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      defaultWeightKg: defaultWeightKg,
      weightStepKg: weightStepKg,
      orderPos: orderPos,
      dropCount: dropCount,
    );
    final slot = PlannedExercise(
      programExerciseId: programExerciseId,
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      defaultWeightKg: defaultWeightKg,
      weightStepKg: weightStepKg,
      isOverridden: true,
      position: orderPos,
      isInserted: true,
      dropCount: dropCount,
    );
    final newQueue = [...current.queue, slot]
      ..sort((a, b) => a.position.compareTo(b.position));
    final next = current.copyWith(queue: newQueue);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Apply session-scoped overrides to the planned queue.
  ///
  /// The program template is fixed once a workout starts, but a lifter can
  /// swap any slot mid-session (smith machine occupied → switch to the
  /// plate-loaded variant). Each override targets one [PlannedExercise] by
  /// its `programExerciseId`. Unaffected slots are returned unchanged.
  List<PlannedExercise> _applyOverrides(
    List<ProgramExerciseView> planned,
    List<SessionExerciseOverride> overrides,
  ) {
    if (overrides.isEmpty) {
      return planned.map(PlannedExercise.fromView).toList();
    }
    final byPeId = {for (final o in overrides) o.programExerciseId: o};
    return planned.map((v) {
      final base = PlannedExercise.fromView(v);
      final o = byPeId[v.pe.id];
      if (o == null) return base;
      return base.copyWith(
        exerciseId: o.exerciseId,
        exerciseName: o.exerciseName,
        targetSets: o.targetSets,
        targetRepsMin: o.targetRepsMin,
        targetRepsMax: o.targetRepsMax,
        defaultWeightKg: o.defaultWeightKg,
        weightStepKg: o.weightStepKg,
        isOverridden: true,
        previousExerciseId: o.previousExerciseId,
        skipped: o.skipped,
        dropCount: o.dropCount,
      );
    }).toList();
  }

  /// Build the full session queue from the program template + overrides:
  /// template slots (overrides applied in place) PLUS session-only inserted
  /// exercises (override rows with `inserted = 1`, which match no template
  /// slot), all merged and sorted by `position`. The cursor logic works off
  /// list order, so keeping the list position-sorted is what makes an inserted
  /// exercise land where the user put it (and survive resume).
  List<PlannedExercise> _buildQueue(
    List<ProgramExerciseView> planned,
    List<SessionExerciseOverride> overrides,
  ) {
    final slots = _applyOverrides(planned, overrides);
    for (final o in overrides) {
      if (!o.inserted) continue;
      slots.add(PlannedExercise(
        programExerciseId: o.programExerciseId,
        exerciseId: o.exerciseId,
        exerciseName: o.exerciseName,
        targetSets: o.targetSets,
        targetRepsMin: o.targetRepsMin,
        targetRepsMax: o.targetRepsMax,
        defaultWeightKg: o.defaultWeightKg,
        weightStepKg: o.weightStepKg,
        isOverridden: true,
        previousExerciseId: o.previousExerciseId,
        skipped: o.skipped,
        position: o.orderPos ?? double.maxFinite,
        isInserted: true,
        dropCount: o.dropCount,
      ));
    }
    slots.sort((a, b) => a.position.compareTo(b.position));
    return slots;
  }

  /// Substitute one queue slot with a different exercise for this session
  /// only. The program template is never modified. Logged sets prior to
  /// the swap retain their original `exercise_id` — they show up under the
  /// old exercise in the summary, which is honest history.
  ///
  /// The cursor stays at the same queue index; the new exercise's set
  /// count starts from zero (the cursor-advance logic already keys on
  /// `pe.exerciseId`).
  Future<void> substituteExercise({
    required int queueIdx,
    required String exerciseName,
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required double defaultWeightKg,
    double? weightStepKg,
    int dropCount = 0,
  }) async {
    final current = state.value;
    if (current == null) return;
    if (queueIdx < 0 || queueIdx >= current.queue.length) return;
    final slot = current.queue[queueIdx];
    final exercise = await _programDao.findOrCreateExercise(exerciseName);

    // Same-exercise guard: when the resolved exercise is the one already in the
    // slot, this is a target-only edit (sets/reps/weight), NOT a substitution.
    // Pointing `previousExerciseId` at the current exercise would make the
    // "PREVIOUS: N SETS" banner mis-attribute the live sets to a "previous"
    // exercise that is in fact the current one. So we keep the slot's existing
    // swap lineage instead of fabricating one.
    final sameExercise = exercise.id == slot.exerciseId;
    final newPreviousExerciseId =
        sameExercise ? slot.previousExerciseId : slot.exerciseId;

    await _workoutDao.upsertOverride(
      sessionId: current.sessionId,
      programExerciseId: slot.programExerciseId,
      exerciseId: exercise.id,
      previousExerciseId: newPreviousExerciseId,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      defaultWeightKg: defaultWeightKg,
      weightStepKg: weightStepKg,
      skipped: slot.skipped,
      inserted: slot.isInserted,
      orderPos: slot.isInserted ? slot.position : null,
      dropCount: dropCount,
    );
    final replaced = slot.copyWith(
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      defaultWeightKg: defaultWeightKg,
      weightStepKg: weightStepKg,
      isOverridden: true,
      previousExerciseId: newPreviousExerciseId,
      dropCount: dropCount,
    );
    final newQueue = [...current.queue]..[queueIdx] = replaced;
    final next = current.copyWith(queue: newQueue);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Remove the session override on a slot and restore the planned exercise.
  /// Logged sets under the substitute are left in the database — they
  /// remain visible in the summary and contribute to that substitute
  /// exercise's history. Reverting only affects the queue going forward.
  Future<void> revertSubstitution(int queueIdx) async {
    final current = state.value;
    if (current == null) return;
    if (queueIdx < 0 || queueIdx >= current.queue.length) return;
    final slot = current.queue[queueIdx];
    if (!slot.isOverridden) return;
    // An inserted exercise has no plan to revert to — leave it (the UI hides
    // "revert" for inserted slots; this guards the path defensively).
    if (slot.isInserted) return;
    await _workoutDao.deleteOverride(
      sessionId: current.sessionId,
      programExerciseId: slot.programExerciseId,
    );
    // Rebuild this single queue item from the planned program. We refetch
    // all planned exercises for the day and pick the one matching this
    // slot's programExerciseId — cheap on a typical workout day.
    final planned =
        await _programDao.listProgramExercises(current.programDayId);
    final original = planned.firstWhere(
      (v) => v.pe.id == slot.programExerciseId,
      orElse: () => throw StateError(
          'Cannot revert: program exercise no longer exists.'),
    );
    final restored = PlannedExercise.fromView(original);
    final newQueue = [...current.queue]..[queueIdx] = restored;
    final next = current.copyWith(queue: newQueue);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Finish the session (completed). Returns the session ID for navigation.
  Future<String?> finish() async {
    final current = state.value;
    if (current == null) return null;
    await _workoutDao.completeSession(current.sessionId);
    state = const AsyncValue.data(null);
    await _liveActivity.end();
    return current.sessionId;
  }

  Future<void> abandon() async {
    final current = state.value;
    if (current == null) return;
    await _workoutDao.abandonSession(current.sessionId);
    state = const AsyncValue.data(null);
    await _liveActivity.end();
  }
}
