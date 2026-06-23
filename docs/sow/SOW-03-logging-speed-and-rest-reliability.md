# SOW-03 — Logging-Speed Audit + Rest-Timer Reliability

> **Status:** ⬜ Not started · **Phase:** 0 — Existential · **Tier:** Free
> **Owner:** berke · **Est. size:** M
> **Strategic rationale:** Makes the #1 marketing claim ("the fastest logging anywhere") *measurable* and closes the #3 universal complaint ("rest timers break when you switch apps"). Both are core to the speed + trust pillars in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) and the "where LS can surpass" column of [00-competitive-analysis.md](../00-competitive-analysis.md).

This is an **audit + hardening** SOW, not a from-scratch build. Logging and the rest-timer Live Activity already ship (see [02-roadmap.md](../02-roadmap.md) "Already shipped"). The job here is to (a) put a number on "fastest logging anywhere" and shave any friction that fails it, and (b) make the rest timer survive every backgrounding scenario and write down the persistence guarantee so it is testable on a real device.

---

## 1. Goal & Constraints

**What this delivers (user-visible):**
- A measured, enforced **logging-speed budget**: ≤3 taps / ≤3 s to log a routine set; **1 tap** to repeat the last set.
- A **"repeat last set"** affordance and better prefill quality, so the common case (same weight × reps as last set) is a single tap with no wheel scroll.
- A rest timer that **never disappears** when the app is backgrounded, the phone is locked, the user app-switches, or the app is force-killed and relaunched mid-rest — on both the phone Live Activity and the watch.

**Why now:** "Log a set in one crown-twist — the fastest logging anywhere" is the headline App Store claim. If a reviewer counts the taps and the number is unremarkable, the claim is marketing, not product. And the rest-timer-survives-app-switch problem is the single most common cross-app complaint (Strong's data-loss-adjacent timer gripes, FitNotes' FN2 watch "closes between sets"); we can turn it into a *testable* claim no rival advertises.

**Hard constraints:**
- **Free forever.** No part of this is gated. (Non-negotiable #1.)
- **No new dependency.** Persistence reuses `shared_preferences` (already in the tree via `settings_repository.dart`); the Live Activity stays on `live_activities ^2.4.0`.
- **Do not add taps.** Every change must hold or *lower* the tap count in §4's table. A "repeat last set" path that takes 2 taps is a failure.
- **Must work on the watch.** The crown flow in `SetLoggerView.swift` is half the speed claim; it gets the same audit.
- **Demonstrable on a real device.** Every persistence guarantee in §5 has a row in the §8 manual matrix that a human runs on hardware (Live Activities and force-kill behavior cannot be verified in the simulator or in widget tests).

**Non-goals:**
- No redesign of the wheel sheet's visual language (it stays the `set_log_sheet.dart` Cupertino-picker layout).
- No auto rep-detection / sensor logging (explicitly "watch, don't build" in [00-competitive-analysis.md](../00-competitive-analysis.md)).
- No push-driven Live Activity updates — we keep `iOSEnableRemoteUpdates: false` (the app drives updates locally; remote push needs an entitlement we deliberately don't add). See [SOW-05](SOW-05-sync-reliability-and-trust-claims.md) for the broader sync story.
- No change to rest *default* configuration UX (`settings_screen.dart` rest picker stays as is).

## 2. Competitive context

| Rival | Logging speed | Rest timer reliability | Our opening |
|---|---|---|---|
| **Strong** | Fastest tap logger; praised | Timer well-regarded; runs as Live Activity | Match the timer, then **add the testable "survives app-switch + lock + kill" claim** Strong doesn't advertise |
| **Hevy** | Fast, but "overbuilt over time" | Good, but no crown path | We're faster on the wrist; same reliability bar |
| **FitNotes (FN2 watch)** | Dated | **Watch "closes between sets"** | Our watch rest banner persists; theirs doesn't |
| **Setgraph** | Minimalist twin; **best Live Activity** | Strong Live Activity | Equal the Live Activity, beat it on the crown + the explicit guarantee |
| **RP / Juggernaut** | — | **No timer at all** | Pure win; not a contest |

- **Match** = our timer keeps ticking through background, lock, and app-switch exactly like Strong's, and our routine-set log is ≤3 taps like the fastest loggers.
- **Surpass** = (1) the **1-tap repeat-last-set** path, which no crown-driven rival has, and (2) a **published persistence guarantee** (the §5 matrix) that survives *force-kill*, which is the one case rivals quietly lose.

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Tap budget | **≤3 taps / ≤3 s** routine set; **1 tap** repeat-last-set | A concrete, reviewable number; anchors the "fastest logging" claim to something measurable |
| 2 | Repeat-last-set surface | A **secondary 1-tap button** beside `LOG SET` that logs reps+weight+RIR of the last set for this exercise verbatim, then starts rest | One tap, no sheet, no wheel; the highest-leverage speed win |
| 3 | Prefill quality | Prefill **reps and RIR from the last set of this exercise** (not just weight), falling back to target-mid / 0 only when there's no history | Today only weight is prefilled (`active_workout_screen.dart` passes `initialReps: null`); fixing this means the wheel is *already on the right numbers*, so most logs are zero-scroll |
| 4 | Rest-timer persistence store | **`shared_preferences`** key `active_rest_ends_at_ms` (epoch ms) | No new dependency; mirrors the existing `settings_repository.dart` persistence pattern; survives force-kill because it's on disk |
| 5 | Rest restore trigger | Rehydrate on `RestTimerController.build()` **and** on app-resume via a lifecycle observer | `build()` covers cold relaunch after kill; resume covers the long-background case where the in-memory `_expiryTimer` may have been suspended |
| 6 | Source of truth for an *expired* rest | If the stored `endsAt` is in the past at restore, **clear it** (don't show a stale `0:00`) | Matches the existing guard in `WorkoutVM.hasRest` and `applyRemoteRest` |
| 7 | Live Activity update model | **Keep `iOSEnableRemoteUpdates: false`** | Native `Text(timerInterval:)` already counts down without the app running; no push entitlement to add |
| 8 | Instrumentation | A **debug-only tap counter** assertion in widget tests, not shipped telemetry | We measure taps in test + a manual stopwatch row; we do **not** add analytics SDKs (trust pillar) |

## 4. Design & UX

### 4a. The measured tap budget (current → target)

Tap = a discrete finger-down the user must perform. Wheel **scrolls** are counted separately because in the common case good prefill makes them zero.

| Logging path | Today (taps) | Today (wheel scrolls) | Target (taps) | Target (scrolls, common case) |
|---|---|---|---|---|
| **Routine set, values match last** | 2 (`LOG SET` → `SAVE SET`) | 0–3 (weight prefilled; reps/RIR reset → usually scrolled) | **1** (new `REPEAT` button) | **0** |
| **Routine set, weight or reps changed** | 2 | 1–3 | **≤3** (open → adjust wheel → save) | 1–2 (only the changed dial moves) |
| **First set of an exercise (no history)** | 2 | 2–4 (reps reset to target-mid, weight to default) | **≤3** | 1–3 (prefill from target) |
| **Edit a logged set** | 2 (tap row → `SAVE SET`) | 0–3 | **2** (unchanged) | 0–1 |
| **Watch — routine set (crown)** | 1 button + 3 crown dials + Save | n/a (crown) | hold; verify ≤ phone | n/a |

**Reading the table:** the routine-set path is *already* 2 taps, which is good — the friction is the **wheel scrolling** caused by poor prefill (reps reset to target-mid, RIR reset to 0; see `active_workout_screen.dart:443-446` passing `initialReps: null, initialRir: 0`). Decisions #2 and #3 attack the scrolls, not the taps:
- **Repeat-last-set (#2)** removes the sheet entirely for the most common case → 1 tap, 0 scrolls.
- **Better prefill (#3)** means when the user *does* open the sheet, the wheels already read the last set's reps + RIR, so only a genuinely changed dial moves.

### 4b. Repeat-last-set affordance

The active-workout footer CTA today is a single full-width `LOG SET` button (`active_workout_screen.dart:328-340`). Add a compact secondary button to its left, shown **only when a last set exists for the current exercise** and the exercise is not a drop set (drop sets keep their guided chain):

```
┌───────────────────────────────────────────────┐
│  [ ⟳ 80×8 ]   [        LOG SET        ]         │   ← ⟳ = repeat last set (1 tap)
└───────────────────────────────────────────────┘
        │                    │
   logs 80kg × 8 · RIR n     opens the wheel sheet
   verbatim, starts rest     (the existing path)
```

- The `⟳ 80×8` chip shows the last set's weight × reps so the user knows what they're repeating before they tap (no surprise).
- Tapping it calls the same `logSet(...)` + `start(restSeconds)` the sheet's save path uses — identical downstream behavior, just no sheet.
- Maps to the design system: chip uses `LsType.monoData` for the numerals, `t.accent.accent` border, `LsRadius.r3`, `LsSpace` gaps — consistent with the `MetaPill` / `SetChip` family already in the file.

### 4c. Rest-timer reliability UX

No new UI — the fix is invisible when it works. The guarantee is: **whatever state the rest banner / Live Activity / watch rest pill was in, it is exactly that state after any interruption.** The only user-visible change is the *absence* of the bug: rest no longer vanishes after force-kill + relaunch.

### 4d. Watch crown flow audit (no code change expected, but verified)

`SetLoggerView.swift` is a one-input-per-screen pager (REPS → WEIGHT → RIR) driven by the crown and vertical swipe, with `.success` haptic on save (`SetLoggerView.swift:306`) and `.click` on step-cycle (`:260`). The audit confirms it's fast in **chalked / gloved / noisy** conditions:
- Crown input needs no precise touch target (chalk-proof) — confirmed by design; the audit's job is to **measure** it against the phone in §8.
- The prefill parity fix (#3) is mirrored on the watch: `SetLoggerView.swift:277-294` already prefills reps to target-mid and weight from `loggedSets.last`; align it to prefill **reps + RIR from the last set** too, so the crown starts on the right number.

## 5. Data & schema changes

**No SQLite schema change.** Rest-timer persistence is a single scalar, not relational data — it belongs in `shared_preferences`, not a migrated table.

**New `shared_preferences` key (via the `settings_repository.dart` pattern):**

| Key | Type | Meaning |
|---|---|---|
| `active_rest_ends_at_ms` | `int` (epoch ms) | The current rest's absolute end time. Absent / `0` / past = no active rest. Written on every `start` / `adjust` / `dismiss` / `applyRemoteRest`; read on `RestTimerController.build()` and on app-resume. |

This key is **session-scoped in spirit** but stored flat; it is cleared on `dismiss`, on natural expiry, and on workout `finish` / `abandon` (the existing `restTimerProvider.notifier.dismiss()` calls at `active_workout_screen.dart:60,618` already fire those paths — they just need to also clear the pref). No Pigeon / watch-bridge contract change: the watch already receives `restEndsAtMs` via the existing snapshot (`watch_snapshot.dart:33-34,47`) and sends it back via `restSet` (`watch_sync_controller.dart:167-169`).

### The persistence guarantee matrix

This is the testable claim. `endsAt` is the absolute epoch time the rest ends; the countdown is always derived from `now` vs `endsAt`, never from a decrementing counter.

| Scenario | What must survive | Mechanism | Guarantee |
|---|---|---|---|
| **App backgrounded** (home button, still in memory) | Live Activity countdown keeps ticking; in-app banner correct on return | iOS renders `Text(timerInterval: …countsDown:true)` natively from app-group `UserDefaults` (`WorkoutLiveActivity.swift:165,447,472,481`) — no app code runs; in-app banner recomputes from `endsAt` | ✅ Already works (verify, don't rebuild) |
| **Phone locked** | Lock-screen Live Activity countdown ticks | Same native timer-interval rendering on the lock screen | ✅ Already works (verify) |
| **App-switched** (another app foreground) | Live Activity + Dynamic Island countdown tick | Same; the app-group snapshot is already written | ✅ Already works (verify) |
| **Long background → resume** (>5 min, in-memory timer may be suspended) | In-app banner + `_expiryTimer` correct on resume | New lifecycle observer re-reads `endsAt` and calls `_rescheduleExpiry()` on resume | 🔧 New: resume rehydrate |
| **Force-kill → relaunch mid-rest** | Rest reappears with the correct remaining time on both phone and watch | `RestTimerController.build()` reads `active_rest_ends_at_ms`; if future, restores state + reschedules expiry + re-pushes Live Activity | 🔧 **New: the core fix** |
| **Rest expires while killed** | App shows *no* stale rest on relaunch | `build()` sees a past `endsAt` → clears the pref (decision #6) | 🔧 New |
| **Watch + phone both showing rest** | Both show the same countdown; adjusting on one updates the other | Existing last-writer-wins `applyRemoteRest` (`rest_timer_controller.dart:70-81`) + the snapshot push; the pref write is added to that path | 🔧 Harden: persist on the remote-apply path too |

The honest boundary, stated plainly so we don't over-claim: **a force-kill that happens while rest is running is recovered on next launch, but the Live Activity itself ends when iOS terminates the app** (an OS guarantee we can't override without push). So the precise claim is *"reopen the app and your rest is exactly where it should be — to the second."* not *"the lock-screen widget survives a force-kill."* The watch rest pill, driven independently, also re-derives from `endsAt` on its next snapshot.

## 6. Implementation plan

Ordered by layer. Files named are the ones that exist today.

1. **`application/rest_timer_controller.dart`** (core fix):
   - Inject `SharedPreferences` (via the existing `sharedPreferencesProvider` from `main.dart`).
   - `build()`: read `active_rest_ends_at_ms`; if it's in the future, set `state`, call `_rescheduleExpiry()`, and `_pushToLiveActivity()`; if past/absent, clear it and return empty.
   - Add a private `_persist()` helper that writes (or removes) the key; call it from `start`, `adjust`, `dismiss`, `_onExpiry`, and `applyRemoteRest`.
2. **`application/` — app-resume rehydrate:** add an `AppLifecycleListener` (Flutter first-party, no dependency) wired at app root that, on `resumed`, calls `ref.read(restTimerProvider.notifier)` to re-read the pref and reschedule expiry. (Mirrors decision #5; covers the suspended-`_expiryTimer` case.)
3. **`presentation/active_workout_screen.dart`** (repeat-last-set):
   - In `_exerciseView`, compute `lastSetForExercise(current.exerciseId)` (already fetched lazily in `_openSetLogSheet:435`; lift it to a provider read so the footer can show the chip).
   - Render the `⟳ {weight}×{reps}` secondary button to the left of `LOG SET` when a last set exists and `!current.isDropSet`.
   - On tap: call `activeSessionProvider.notifier.logSet(...)` with the last set's values, then `restTimerProvider.notifier.start(restSeconds)` — reuse the exact tail of `_openSetLogSheet:448-454`. Factor that tail into a private `_commitSet(reps, weightKg, rir)` so both the sheet path and the repeat path share it.
4. **`presentation/active_workout_screen.dart` + `presentation/set_log_sheet.dart`** (prefill quality):
   - In `_openSetLogSheet`, pass `initialReps: last?.reps` and `initialRir: last?.rir ?? 0` (today both are hardcoded to null/0 at `:443-446`). The sheet already clamps and falls back to target-mid when `initialReps` is null, so no sheet change is strictly required — but verify the fallback path in `set_log_sheet.dart:107-111`.
5. **Watch (`ios/LSWatch Watch App/SetLoggerView.swift`)** (prefill parity):
   - In `prefill()` (`:265-295`), set `topRir` and the top entry's `reps` from `ex.loggedSets.last` when present, not just `weightKg`. Small, mirrors decision #3.
6. **Instrumentation (test-only):** a widget-test helper that drives the routine-set and repeat paths and asserts the number of `tap` calls is within budget (decision #8). No shipped telemetry.

## 7. Acceptance criteria

- [ ] Logging a routine set whose values match the last set is **1 tap** (the `⟳` button) and starts rest, with **0 wheel scrolls**.
- [ ] Opening the wheel sheet for an exercise with history shows the **reps and RIR of the last set** already selected (not target-mid / 0).
- [ ] The full routine-set-via-sheet path is **≤3 taps and completes in ≤3 s** by stopwatch on a real device.
- [ ] The `⟳` button is hidden when there is no prior set for the current exercise, and for drop-set exercises.
- [ ] Force-killing the app mid-rest and relaunching restores the rest banner with the **correct remaining time** (within 1 s) on the phone.
- [ ] If the rest had already expired during the kill, **no rest banner appears** on relaunch (no stale `0:00`).
- [ ] Backgrounding, locking, and app-switching during rest all keep the Live Activity / Dynamic Island countdown ticking (verified on hardware).
- [ ] Adjusting rest on the watch updates the phone (and vice-versa), and the adjusted value survives a force-kill + relaunch.
- [ ] The watch crown logger prefills reps + RIR from the last set, matching the phone.
- [ ] No new third-party dependency added; `pubspec.yaml` diff is empty for runtime deps.

## 8. Testing

**Unit (in-memory `sqflite_ffi` + a fake/`SharedPreferences.setMockInitialValues`, mirroring `test/dao_test.dart` / `test/workout_progress_test.dart`):**
- `cursorAfter` / `_commitSet` unchanged — add a test that the repeat path produces an identical `WorkoutSet` to the sheet path given the same values.
- `RestTimerController`: starting writes the pref; `build()` with a future `active_rest_ends_at_ms` restores a `running` state; with a past value returns empty **and** clears the key; `dismiss` / `_onExpiry` clear the key.
- `applyRemoteRest` with a future ms persists; with a past ms clears.

**Widget:**
- The `⟳` button appears only with history and for non-drop-set exercises; tapping it logs the last set's values and starts rest (mock the controller).
- The tap-budget assertion helper (decision #8) for the routine and repeat paths.
- Sheet prefill: given a last set of `(reps: 7, rir: 2)`, the reps/RIR wheels initialize to 7 / 2.

**Manual matrix (real device — the load-bearing tests; Live Activities and force-kill cannot be widget-tested):**

| # | Steps | Expected |
|---|---|---|
| M1 | Log a set → press home → wait 30 s | Lock-screen Live Activity counts down correctly |
| M2 | Log a set → lock phone → observe lock screen | Countdown ticks on the lock screen |
| M3 | Log a set → open another app → check Dynamic Island | Compact/expanded countdown ticks |
| M4 | Log a set → background app 6 min → reopen | In-app banner shows correct remaining (or cleared if expired) |
| M5 | Log a set → **force-kill** → relaunch (rest still active) | Rest banner restores within 1 s of the true remaining time |
| M6 | Log a set with 10 s rest → **force-kill** → relaunch after 15 s | No rest banner (cleared, no stale `0:00`) |
| M7 | Start rest on phone → adjust −15 s on watch → check phone | Phone reflects the adjusted end time |
| M8 | Start rest → adjust on watch → **force-kill phone** → relaunch | Restored rest reflects the watch-adjusted time |
| M9 | Stopwatch: log a routine set via the sheet | ≤3 s, ≤3 taps |
| M10 | Stopwatch: tap `⟳` repeat-last-set | 1 tap, rest starts, set logged correctly |
| M11 | Crown log on watch with chalked/gloved hand | Completes without mis-taps; time ≈ phone |

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Over-claiming "survives force-kill" when iOS actually ends the Live Activity on termination | Med | State the precise claim (§5 boundary): *reopen and rest is exact*, not *the widget survives kill*. Marketing copy reviewed against the matrix. |
| `SharedPreferences` write lands after a crash, leaving a stale `endsAt` | Low | `build()` and resume both **validate against `now`** and clear past values (decision #6) — a stale write is self-healing on next read. |
| Repeat-last-set adds visual clutter / a second CTA dilutes the primary action | Med | Compact chip, not a co-equal button; hidden when no history; minimalism guardrail (non-negotiable #4) — re-evaluate if it crowds the footer on small devices. |
| Resume lifecycle observer double-fires and re-pushes the Live Activity redundantly | Low | The Live Activity controller already serializes updates through a single-slot queue (`live_activity_controller.dart:29-34`); a redundant push is a no-op write. |
| Prefill from last set surprises a user who wants a fresh number every set | Low | Wheels remain freely scrollable; prefill only changes the *starting* position, never commits anything. |
| Watch/phone rest race on simultaneous adjust | Low | Existing last-writer-wins `applyRemoteRest` is unchanged; we only add a pref write to that path. |

## 10. Definition of done

- The §7 acceptance criteria pass, including the full §8 manual matrix on a real iPhone + paired Apple Watch.
- The tap budget in §4a is met and documented, so the App Store claim "log a set in one tap — the fastest logging anywhere" is backed by M9/M10.
- The persistence guarantee matrix (§5) is true on hardware, unlocking the testable trust claim *"reopen the app and your rest timer is exactly where it should be — even after a force-quit"* — a claim no rival advertises.
- Update [02-roadmap.md](../02-roadmap.md): flip **SOW-03** to `✅ Shipped` and note that the logging-speed + rest-reliability Phase 0 gate is cleared.
