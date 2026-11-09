import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart' show databaseProvider;
import '../../history/application/history_provider.dart'
    show historyListProvider;
import '../../home/application/home_provider.dart'
    show lastSessionSummaryProvider;
import '../../programs/application/programs_provider.dart';
import '../../programs/data/program_dao.dart';
import '../../programs/domain/program_exercise.dart';
import '../../programs/domain/program_exercise_variant.dart';
import '../../stats/application/stats_provider.dart'
    show exerciseProgressionProvider, loggedExercisesProvider;
import '../data/workout_dao.dart';
import '../domain/active_session.dart';
import '../domain/session_exercise_override.dart';
import '../domain/workout_session.dart';
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

/// Set target for [toExerciseId] when a slot switches between its members
/// (base, variants — and every exercise it ran this session, "Change
/// exercise" swaps included: [PlannedExercise.slotExerciseIds]), so the sets
/// already done on the slot count instead of restarting (SOW-14). Pure +
/// top-level for tests.
///
/// Switching to member M means "do M's prescription for the rest of this slot"
/// (DEC-0007 #13): M's planned set count — its own, or the slot's when it
/// inherits — minus every set already done on the slot's OTHER exercises, and
/// never below what M itself already has:
///
///     max(doneOn(M), M.targetSets − Σ doneOn(other slot exercises))
///
/// Base Bar (plan 3) → Change exercise to Cable, 2 logged → Machine: 1 →
/// back to Bar: still 1 — the Cable sets stay counted though the override
/// row's two links no longer name Cable (D-0016 review #1).
///
/// Base 3 → variant 4 with 1 done on the base → 3 on the variant; base 4 →
/// variant 2 with 3 done → 0: the slot counts as complete under M's plan,
/// which [PlannedExercise.canSwitchTo] refuses up front (review #2: no
/// inflation on a complete slot). The result depends only on the logged sets
/// and M's plan, so round trips cannot drift; a session "Add set" stays with
/// the member it was made on. Completed sets count distinct groups, so a drop
/// set counts once.
int carryOverTargetSets(
  PlannedExercise slot,
  String toExerciseId,
  List<WorkoutSet> logged,
) {
  SlotVariant? to;
  for (final m in slot.members) {
    if (m.exerciseId == toExerciseId) to = m;
  }
  final planned = to == null ? slot.targetSets : slot.prescriptionOf(to).sets;
  final others = slot.slotExerciseIds..remove(toExerciseId);
  var doneElsewhere = 0;
  for (final id in others) {
    doneElsewhere += completedSetsFor(logged, id);
  }
  final doneOnNew = completedSetsFor(logged, toExerciseId);
  final target = planned - doneElsewhere;
  return target < doneOnNew ? doneOnNew : target;
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

/// The single most-recent set ever logged for [exerciseId] (across all
/// sessions), or null when the exercise has no history. Feeds the active-
/// workout footer's 1-tap "repeat last set" chip (SOW-03). The in-session last
/// set, when one exists, takes precedence at the call site.
///
/// Not autoDispose, so it is invalidated (with [lastWeightForExerciseProvider])
/// whenever a set is written or a workout ends — see
/// [ActiveWorkoutController]. Otherwise a lookup made while an exercise had no
/// history (every first switch to a new variant) cached that "nothing" for the
/// whole process and the chip never appeared later (QA VAR-04).
final lastSetForExerciseProvider =
    FutureProvider.family<WorkoutSet?, String>((ref, exerciseId) {
  return ref.watch(workoutDaoProvider).lastSetForExercise(exerciseId);
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

  /// Drop the cached "last set / last weight" lookups after a set is written
  /// or a workout ends, so the next lookup reads the DB (QA VAR-04).
  void _invalidateLastSets() {
    ref.invalidate(lastSetForExerciseProvider);
    ref.invalidate(lastWeightForExerciseProvider);
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
    if (session == null) return null;
    if (session.programDayId == null) {
      // Its program/day was deleted mid-workout (the delete detaches sessions
      // rather than failing) and the app was killed before the delete could
      // close it (see [closeIfDetached]).
      await _closeDetached(session.id);
      return null;
    }

    final planned = await _programDao.listProgramExercises(session.programDayId!);
    final overrides = await _workoutDao.overridesForSession(session.id);
    final variants =
        await _programDao.listVariantsForDay(session.programDayId!);
    final queue = _buildQueue(planned, overrides, variants);
    final loggedSets = await _workoutDao.setsForSession(session.id);
    if (queue.isEmpty && loggedSets.isEmpty) {
      // Nothing to do and nothing logged — abandon. With sets logged the
      // workout stays open on an empty queue (ALL DONE → FINISH): the day's
      // last exercise was deleted mid-workout (SOW-15). Abandoning it here
      // used to drop those sets out of History, PRs and Stats.
      await _workoutDao.abandonSession(session.id);
      return null;
    }
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

  /// Close a session whose program day is gone. There is no plan to rebuild a
  /// queue from, and leaving it `active` would block every new workout. Keep
  /// whatever was logged — complete it, ended at its last set (not "now", so
  /// the duration stays honest), so the sets stay in History — else drop it.
  /// Then tear down like [finish]: rest timer and Live Activity (all of them —
  /// on a cold start the activity belongs to the previous process).
  Future<void> _closeDetached(String sessionId) async {
    final sets = await _workoutDao.setsForSession(sessionId);
    if (sets.isEmpty) {
      await _workoutDao.abandonSession(sessionId);
    } else {
      var last = sets.first.loggedAt;
      for (final s in sets) {
        if (s.loggedAt.isAfter(last)) last = s.loggedAt;
      }
      await _workoutDao.completeSession(sessionId, endedAt: last);
    }
    // What aggregates completed sessions may have been read before the close
    // (on a cold start Home's LAST strip races the resume — QA RISK-05).
    ref
      ..invalidate(lastSessionSummaryProvider)
      ..invalidate(historyListProvider)
      ..invalidate(loggedExercisesProvider)
      ..invalidate(exerciseProgressionProvider);
    ref.read(restTimerProvider.notifier).dismiss();
    await _liveActivity.endAll();
  }

  /// After a program or day delete: if the running workout lost its day,
  /// close it now (same rule as on resume) instead of offering RESUME until
  /// the next cold start. Returns whether it closed one.
  Future<bool> closeIfDetached() async {
    final current = state.value;
    if (current == null) return false;
    final session = await _workoutDao.findSession(current.sessionId);
    if (session == null ||
        session.status != SessionStatus.active ||
        session.programDayId != null) {
      return false;
    }
    state = const AsyncValue.data(null);
    await _closeDetached(session.id);
    return true;
  }

  /// After a slot was deleted from the program (SOW-15): drop every template
  /// slot of the running workout whose program row is gone. Inserted
  /// exercises have no program row and stay. Logged sets are kept — they are
  /// keyed by exercise, not by slot. The slot's override row was marked
  /// dropped by [ProgramDao.deleteProgramExercise] and is ignored from here
  /// on, since the queue is built from the plan.
  ///
  /// Cursor: a kept current slot stays current. If the current slot was
  /// dropped, the cursor moves to the next remaining slot that isn't skipped
  /// or complete; with none after it, to the first slot with sets left ([cursorAfter]) —
  /// or the finished state, where the workout stays open and FINISH still
  /// works — unless nothing was logged, in which case it is abandoned, the
  /// same rule as on resume. The Live Activity is updated here and the watch
  /// snapshot follows the state change, so neither keeps showing the dropped
  /// slot. Returns whether anything was dropped.
  Future<bool> dropDeletedSlots() async {
    final current = state.value;
    if (current == null) return false;
    final planned =
        await _programDao.listProgramExercises(current.programDayId);
    final live = {for (final v in planned) v.pe.id};
    // Re-read: the state may have moved while the plan was loading.
    final now = state.value;
    if (now == null || now.sessionId != current.sessionId) return false;
    final oldIdx = now.cursor.exerciseIdx;
    final kept = <PlannedExercise>[];
    var keptCurrent = -1;
    var keptBefore = 0;
    for (var i = 0; i < now.queue.length; i++) {
      final slot = now.queue[i];
      if (!slot.isInserted && !live.contains(slot.programExerciseId)) continue;
      if (i == oldIdx) keptCurrent = kept.length;
      if (i < oldIdx) keptBefore++;
      kept.add(slot);
    }
    if (kept.length == now.queue.length) return false;
    if (kept.isEmpty && now.loggedSets.isEmpty) {
      // Nothing left and nothing logged (inserted exercises are always kept,
      // so none was inserted either): abandon now, as a resume would, rather
      // than let FINISH save an empty workout (D-0017 review #5). [abandon]
      // clears the rest timer and ends the Live Activity; Home and the
      // workout screen follow the state to null, as after a day delete.
      await abandon();
      return true;
    }

    final Cursor cursor;
    if (keptCurrent >= 0) {
      cursor = now.cursor.copyWith(exerciseIdx: keptCurrent);
    } else if (oldIdx >= now.queue.length) {
      cursor = Cursor(exerciseIdx: kept.length, setIdx: 0);
    } else {
      var idx = keptBefore;
      // Walk past skipped and already complete slots (D-0017 review #2:
      // landing on a done slot showed set 3/2).
      while (idx < kept.length &&
          (kept[idx].skipped || kept[idx].isCompleteIn(now.loggedSets))) {
        idx++;
      }
      cursor = idx < kept.length
          ? Cursor(
              exerciseIdx: idx,
              setIdx: completedSetsFor(now.loggedSets, kept[idx].exerciseId),
            )
          : cursorAfter(kept, now.loggedSets);
    }
    final next = now.copyWith(queue: kept, cursor: cursor);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
    return true;
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
      final variants = await _programDao.listVariantsForDay(programDayId);
      final session = await _workoutDao.startSession(programDayId);
      final created = ActiveSession(
        sessionId: session.id,
        programDayId: programDayId,
        startedAt: session.startedAt,
        queue: [
          for (final v in planned)
            PlannedExercise.fromView(v, variants: variants[v.pe.id] ?? const []),
        ],
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
    _invalidateLastSets();
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
    _invalidateLastSets();
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
    _invalidateLastSets();
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
    _invalidateLastSets();
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
    _invalidateLastSets();
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
    _invalidateLastSets();
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
    _invalidateLastSets();
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
      ranExerciseIds: slot.ranExerciseIds,
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
      _invalidateLastSets();
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
      ranExerciseIds: slot.ranExerciseIds,
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
    Map<String, List<ProgramExerciseVariantView>> variants,
  ) {
    final byPeId = {for (final o in overrides) o.programExerciseId: o};
    return planned.map((v) {
      final base = PlannedExercise.fromView(
        v,
        variants: variants[v.pe.id] ?? const [],
      );
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
        ranExerciseIds: o.ranExerciseIds,
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
    Map<String, List<ProgramExerciseVariantView>> variants,
  ) {
    final slots = _applyOverrides(planned, overrides, variants);
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
        ranExerciseIds: o.ranExerciseIds,
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
    // Keep the whole chain, not just the last link (D-0016 review #1).
    final ran = sameExercise ? slot.ranExerciseIds : slot.ranThrough;

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
      ranExerciseIds: ran,
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
      ranExerciseIds: ran,
    );
    final newQueue = [...current.queue]..[queueIdx] = replaced;
    final next = current.copyWith(queue: newQueue);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Switch a slot to one of its members — the base or a variant (SOW-14).
  /// One tap from the exercise-options menu, no confirm. The member's own
  /// prescription applies for the rest of the slot (DEC-0007 #13): its weight
  /// and step (step falls back to the slot's), its rep range and drop count,
  /// and its set count less the sets done on the other members
  /// ([carryOverTargetSets]). Persisted as a session override like a swap, with
  /// `previous_exercise_id` rotated so the "PREVIOUSLY N SETS ON X" banner
  /// works. Going back to the base with the plan's numbers restored drops the
  /// override entirely, so the tune button returns to neutral. The cursor stays
  /// put; logged sets keep their own exercise.
  Future<void> switchVariant(int queueIdx, String exerciseId) async {
    final current = state.value;
    if (current == null) return;
    if (queueIdx < 0 || queueIdx >= current.queue.length) return;
    final slot = current.queue[queueIdx];
    if (!slot.hasVariants || slot.skipped || exerciseId == slot.exerciseId) {
      return;
    }
    SlotVariant? member;
    for (final m in slot.members) {
      if (m.exerciseId == exerciseId) member = m;
    }
    if (member == null) return;
    // The per-member rule (SOW-14 §3 #6): refused only when the slot is
    // already complete under the member's OWN plan — a switch there would
    // leave nothing to do (review #2: no inflation). Whether the running
    // member is complete doesn't matter.
    if (!slot.canSwitchTo(member, current.loggedSets)) return;

    final plan = slot.prescriptionOf(member);
    final target = carryOverTargetSets(slot, exerciseId, current.loggedSets);
    // Remember what the member we leave ran with (a "Change exercise" weight
    // edit included), and come back to it rather than to the plan (review #3).
    final weights = {
      ...slot.memberWeights,
      slot.exerciseId: MemberWeight(
        weightKg: slot.defaultWeightKg,
        weightStepKg: slot.weightStepKg,
      ),
    };
    final remembered = weights[member.exerciseId];
    final weight = remembered?.weightKg ?? member.defaultWeightKg;
    final step = remembered != null
        ? remembered.weightStepKg
        : (member.weightStepKg ?? slot.baseWeightStepKg);

    if (member.isBase) {
      // Drop the override only when the round trip left no trace: nothing
      // logged on any exercise the slot ran other than the base — variants
      // and swapped-in exercises, even ones it has since left — and every
      // plan value (sets, reps, drops, weight, step) as planned. Otherwise
      // the override stays, so the PREVIOUSLY banner and summary attribution
      // keep those sets and a weight edit survives.
      final loggedOffBase = (slot.slotExerciseIds..remove(member.exerciseId))
          .any((id) => completedSetsFor(current.loggedSets, id) > 0);
      // Compared against the fresh plan row, so a plan edited mid-workout
      // keeps the override too.
      final planned =
          await _programDao.listProgramExercises(current.programDayId);
      ProgramExerciseView? row;
      for (final v in planned) {
        if (v.pe.id == slot.programExerciseId) row = v;
      }
      if (row != null &&
          !loggedOffBase &&
          target == row.pe.targetSets &&
          plan.repsMin == row.pe.targetRepsMin &&
          plan.repsMax == row.pe.targetRepsMax &&
          plan.drops == row.pe.dropCount &&
          weight == row.pe.defaultWeightKg &&
          step == row.pe.weightStepKg) {
        await _workoutDao.deleteOverride(
          sessionId: current.sessionId,
          programExerciseId: slot.programExerciseId,
        );
        final restored = slot.copyWith(
          exerciseId: row.pe.exerciseId,
          exerciseName: row.exerciseName,
          targetSets: row.pe.targetSets,
          targetRepsMin: row.pe.targetRepsMin,
          targetRepsMax: row.pe.targetRepsMax,
          dropCount: row.pe.dropCount,
          defaultWeightKg: row.pe.defaultWeightKg,
          weightStepKg: row.pe.weightStepKg,
          isOverridden: false,
          previousExerciseId: null,
          memberWeights: weights,
          // Nothing was logged off the base, so nothing to remember — and a
          // resume (no override row) would not remember it either.
          ranExerciseIds: const [],
        );
        _replaceSlot(current, queueIdx, restored);
        return;
      }
    }

    await _workoutDao.upsertOverride(
      sessionId: current.sessionId,
      programExerciseId: slot.programExerciseId,
      exerciseId: member.exerciseId,
      previousExerciseId: slot.exerciseId,
      targetSets: target,
      targetRepsMin: plan.repsMin,
      targetRepsMax: plan.repsMax,
      defaultWeightKg: weight,
      weightStepKg: step,
      skipped: false,
      dropCount: plan.drops,
      ranExerciseIds: slot.ranThrough,
    );
    _replaceSlot(
      current,
      queueIdx,
      slot.copyWith(
        exerciseId: member.exerciseId,
        exerciseName: member.name,
        targetSets: target,
        targetRepsMin: plan.repsMin,
        targetRepsMax: plan.repsMax,
        dropCount: plan.drops,
        defaultWeightKg: weight,
        weightStepKg: step,
        isOverridden: true,
        previousExerciseId: slot.exerciseId,
        memberWeights: weights,
        ranExerciseIds: slot.ranThrough,
      ),
    );
  }

  void _replaceSlot(ActiveSession current, int idx, PlannedExercise slot) {
    final newQueue = [...current.queue]..[idx] = slot;
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
    // Resolve the plan FIRST (review #5): rebuild this single queue item from
    // the planned program — refetch the day's slots and pick this one, cheap on
    // a typical day. If the slot was deleted from the program mid-workout
    // there is nothing to revert to: keep the override and the queue as they
    // are, rather than deleting the override and then failing, which left the
    // DB and memory out of sync.
    final planned =
        await _programDao.listProgramExercises(current.programDayId);
    ProgramExerciseView? original;
    for (final v in planned) {
      if (v.pe.id == slot.programExerciseId) original = v;
    }
    if (original == null) return;
    final restored = PlannedExercise.fromView(
      original,
      variants: await _programDao.listVariants(original.pe.id),
    );
    await _workoutDao.deleteOverride(
      sessionId: current.sessionId,
      programExerciseId: slot.programExerciseId,
    );
    final newQueue = [...current.queue]..[queueIdx] = restored;
    final next = current.copyWith(queue: newQueue);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Finish the session (completed). Returns the session ID for navigation.
  Future<String?> finish() async {
    final current = state.value;
    if (current == null) return null;
    // Clear any running rest first so it can't outlive the session — in memory
    // AND on disk (SOW-03 §5: rest is cleared on finish/abandon, else a stored
    // endsAt would resurrect on relaunch or leak into the next workout).
    // Putting this in the controller covers the watch finish/discard paths too,
    // which route through here.
    ref.read(restTimerProvider.notifier).dismiss();
    await _workoutDao.completeSession(current.sessionId);
    state = const AsyncValue.data(null);
    _invalidateLastSets();
    await _liveActivity.end();
    return current.sessionId;
  }

  Future<void> abandon() async {
    final current = state.value;
    if (current == null) return;
    ref.read(restTimerProvider.notifier).dismiss(); // see finish() — SOW-03 §5
    await _workoutDao.abandonSession(current.sessionId);
    state = const AsyncValue.data(null);
    _invalidateLastSets();
    await _liveActivity.end();
  }
}
