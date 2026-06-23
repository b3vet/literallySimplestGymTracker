# SOW-09 — HRV Readiness Modifier

> **Status:** ⬜ Not started · **Phase:** 3 · **Tier:** Paid
> **Owner:** berke · **Est. size:** L
> **Strategic rationale:** Opens the one unoccupied future lane — recovery-aware programming at a minimalist price — that neither Hevy nor Fitbod touches, and pre-empts Apple's rumored AI health coach normalizing HRV-to-intensity. See [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) (Risk #4, the minimalism trap) and [00-competitive-analysis.md](../00-competitive-analysis.md) (Emerging trends — "Recovery-aware HRV programming: nobody does it at a minimalist price → the unoccupied future lane").

This SOW follows [SOW-00-template.md](SOW-00-template.md). It builds directly on the entitlement gate from **[SOW-06 Monetization foundation](SOW-06-monetization-foundation.md)** and modifies the per-set suggestion produced by **[SOW-07 RIR auto-progression](SOW-07-rir-auto-progression.md)**. Both are prerequisites and must ship first (see [02-roadmap.md](../02-roadmap.md): SOW-06 → SOW-07 → SOW-09).

---

## 1. Goal & Constraints

**What this delivers**
- One **bounded, optional pre-workout readiness adjustment**: on the day's first session, read the lifter's overnight HRV (HKQuantityTypeIdentifier `heartRateVariabilitySDNN`) against a rolling personal baseline, and — only when HRV is meaningfully *below* baseline — surface **one** card: e.g. *"HRV ~18% below your 7-day baseline — soften today's top set ~10%, or cap your RIR floor at 2."*
- The card **modifies the SOW-07 RIR auto-progression suggestion** (softens the proposed load step and/or raises the RIR floor for the day) and/or shows a single advisory line. It is **accept-or-ignore**; nothing is auto-applied.
- It **never reprograms the workout** — no set is added/removed, no exercise is swapped, no program is rewritten.

**Why now**
- It's the move neither Hevy (RPE decorative) nor Fitbod (fatigue-blind AI) makes. Cora Health proves it's architecturally feasible — it reads overnight HRV / resting HR / sleep via HealthKit and adjusts *before the app opens* — but **no minimalist logger does it.**
- Apple's rumored AI health coach would normalize HRV-to-intensity and flip this from differentiator to table-stakes. Shipping it while it still differentiates is the bet (see Triggers, §3).

**Hard constraints**
- **Paid.** Gated behind the SOW-06 entitlement. Free tier never sees it.
- **Minimalism guardrail (non-negotiable — README #4):** ONE bounded, optional adjustment, shown **once, pre-workout**. Never a coaching surface, never a daily-readiness-score dashboard, never a trend chart, never auto-applied. The lifter accepts or ignores and that's the entire interaction.
- **No new dependency.** HRV is read through the existing HealthKit integration the watch already uses (`ios/LSWatch Watch App/WorkoutSessionManager.swift`); the phone gains a *read-only discrete query*. No third-party SDK.
- **Graceful degrade.** If HealthKit is unavailable, unauthorized, or there's no overnight HRV sample / no baseline yet, the feature **silently no-ops** — the workout starts exactly as it does today. This mirrors the defensive posture already in `WorkoutSessionManager.swift` ("Nothing here is allowed to crash the app").

**Non-goals**
- No readiness *score* (no 0–100 number, no ring, no "recovery: 73%"). One directional nudge, in plain language.
- No resting-HR / sleep / respiratory-rate fusion in v1 (single-signal: HRV SDNN). Cora-style multi-signal is explicitly deferred.
- No reprogramming, no auto-deload, no auto-applied modifier. No HRV in the summary or stats screens.
- No watch-side readiness UI. The card is **phone-only, pre-workout** (see §3 decision 5 for why HRV is read on the phone, not the watch).

## 2. Competitive context

| App | Recovery-aware programming? | Where it falls short |
|---|---|---|
| **Cora Health** | Yes — reads overnight HRV/RHR/sleep via HealthKit, adjusts before app opens | Not a strength logger; it's a dedicated HRV app — proves feasibility, not our use case |
| **Whoop / Oura** | Yes — proprietary strap/ring, daily "recovery" score | Hardware-gated, subscription, a *dashboard* — the opposite of one invited nudge |
| **Fitbod** | No — AI generation is fatigue-blind | Cold-start, advanced lifters distrust it |
| **Hevy** | No — RPE is decorative, never acted on | Logs effort, ignores recovery |
| **Alpha Progression** | No — RIR auto-progression, but recovery-blind | The rival that could match the watch+RIR wedge; even it has no HRV layer |
| **LS Gym Track** | **One bounded HRV nudge that modifies the RIR suggestion** | — |

- **Match:** read overnight HRV against a personal baseline (everyone capable does this).
- **Surpass:** do it as **one invited, bounded nudge at a minimalist price**, wired into the RIR auto-progression engine — not a hardware-locked recovery dashboard. Nobody occupies "HRV-aware programming, minimalist, on a one-time-purchase logger."

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | HRV metric | **`HKQuantityTypeIdentifier.heartRateVariabilitySDNN`** (read in ms) | The only HRV metric Apple Watch records natively (overnight, during "Breathe"/sleep). It's what every HealthKit HRV consumer (incl. Cora) reads. No derived/computed metric. |
| 2 | "Today's HRV" definition | **Mean of `heartRateVariabilitySDNN` samples in the trailing ~12 h window ending at session start** (typically the most recent overnight readings). If ≥1 sample, use it; else no-op. | Overnight SDNN is the recovery-relevant reading. A short trailing window avoids stale mid-day samples and needs no sleep-stage API. |
| 3 | Baseline window | **Rolling 7-day mean** of daily HRV (today excluded), v1. The 7-vs-28-day window is a **calibration decision** flagged for post-launch tuning; ship 7-day, store enough history to switch to 28-day without a migration. | 7-day reacts to acute fatigue (the point of a *pre-workout* nudge); 28-day is steadier but laggy. Start responsive, tune with real data. |
| 4 | The bounded adjustment + caps | Trigger **only on the downside** when `todayHRV ≤ baseline × (1 − DROP_THRESHOLD)`, `DROP_THRESHOLD = 0.10` (10% below baseline). Effect is **bounded**: soften the SOW-07 proposed top-set load by **`min(10%, proportional-to-drop)`** AND/OR **raise the RIR floor by +1 (cap at floor = 2)** for today only. **Hard caps:** load softening never exceeds **−10%**; RIR floor cap never below 2; never *raises* intensity on a good-HRV day (no upside nudge in v1); fires **at most once per calendar day**. | One bounded, conservative, downside-only adjustment. Capping the magnitude is what keeps this a *nudge*, not a coach. No upside nudge avoids encouraging overreach on a single noisy good reading. |
| 5 | Where HRV is read | **Phone HealthKit, via a discrete `HKSampleQuery`** — NOT the watch live builder. | `heartRateVariabilitySDNN` is an **overnight/at-rest** sample, not a live-workout signal — the watch's `HKLiveWorkoutBuilder` (`WorkoutSessionManager.swift`) only streams live `heartRate` + `activeEnergyBurned` *during* a session, so it cannot supply yesterday's overnight HRV. The phone already syncs all watch-recorded HRV into the shared HealthKit store, so a phone-side query reads it without any watch round-trip or bridge change. |
| 6 | When it's computed/shown | **Once, on the first session start of the calendar day**, before the active-workout screen settles — pre-workout. Subsequent sessions the same day: no card (already fired). | Pre-workout is the only honest place for a readiness call; firing once matches "shown once" guardrail. |
| 7 | Min data to activate | **≥4 of the last 7 days have an HRV reading** (enough for a non-garbage baseline) AND a today reading exists. Otherwise silent no-op, no card, no error. | Avoids a confident nudge off one or two noisy samples — the central HRV-noise risk (§9). |
| 8 | Free/paid boundary | **Paid only**, gated behind the SOW-06 `proEntitlementProvider`. Free users: feature fully invisible, no HealthKit HRV prompt, no card. | "Additive only" monetization (strategy §Monetization). HRV readiness is named in the strategy doc as a paid additive feature; core logging stays free forever. |
| 9 | Acceptance model | **Accept** applies the modifier to *this session's* SOW-07 suggestions; **Ignore** dismisses and the day proceeds with un-modified SOW-07 suggestions. The choice is **session-scoped**, persisted on the session so resume/watch-resync don't re-prompt. | Append-only, phone-as-source-of-truth discipline (README #2). The watch inherits the already-modified suggestion via the normal snapshot; it never computes HRV itself. |

**Triggers (from strategy — record and watch):**
- **Accelerate** if **Apple ships its rumored AI health coach** → HRV-to-intensity becomes table-stakes; pull SOW-09 forward in the roadmap. (Roadmap "Decision-condition triggers": *"Apple ships an AI health coach → SOW-09 HRV becomes table-stakes; accelerate."*)
- **Defer** if **Hevy Trainer adoption proves low** → signals the market doesn't yet value programmed intelligence; hold SOW-09 and reinvest in free table-stakes.

## 4. Design & UX

**Where it lives:** one card presented over/above the active-workout screen (`lib/features/workout/presentation/active_workout_screen.dart`) at first session-start of the day, *before* the first set logger is reachable. Built with the design system (`LsType`, `LsAccent`, `LsSpace`, `r3`) — same accent the user picked, same card treatment as `program_status_sheet.dart`.

**Interaction flow:**
1. User taps "Start workout" on the day → controller starts the session (SOW-07 computes its baseline suggestions).
2. If paid + HRV downside triggers + not yet fired today → present the **Readiness card** once.
3. **Accept** → apply the bounded modifier to this session's SOW-07 suggestions, persist `hrv_decision = accepted`, dismiss. **Ignore** → persist `hrv_decision = ignored`, dismiss, suggestions un-modified.
4. Card never returns this session (or this calendar day). Workout proceeds normally.

**ASCII mock (phone, pre-workout card):**

```
┌─────────────────────────────────────┐
│  READINESS                           │   ← LsType eyebrow, accent ink
│                                      │
│  HRV ~18% below your 7-day baseline  │   ← one plain-language line
│                                      │
│  Suggested today:                    │
│   • Top set softened ~10%            │   ← bounded, ≤10%
│   • RIR floor capped at 2            │   ← cap, today only
│                                      │
│  You can ignore this and train as    │
│  planned.                            │   ← honest opt-out, no pressure
│                                      │
│   ┌─────────────┐   ┌─────────────┐  │
│   │   IGNORE    │   │   ACCEPT    │  │   ← Ignore = default/left, no dark pattern
│   └─────────────┘   └─────────────┘  │
└─────────────────────────────────────┘
```

**How it modifies the SOW-07 suggestion (the only behavioral hook):**
- SOW-07 produces a per-set suggestion (proposed next-session load step + an RIR target/floor). When **Accept** is chosen, the active session carries a `hrvModifier` that the SOW-07 suggestion layer reads:
  - **Load:** `suggestedTopSetKg → suggestedTopSetKg × (1 − softenFraction)`, where `softenFraction = min(0.10, ...)` from decision 4, then re-rounded to the exercise `weightStepKg`.
  - **RIR floor:** `effectiveRirFloor = max(sow07RirFloor, 2)` for today.
- On **Ignore** (or free user, or no trigger), `hrvModifier` is absent and SOW-07 behaves exactly as specified in its own SOW. The two engines are otherwise independent.

**Watch behavior:** none new. The watch receives the *already-modified* suggestions through the normal `WatchSessionSnapshot` push (`pigeons/watch_bridge.dart`) — it never reads HRV, never shows a readiness card, never computes anything. Phone is the source of truth (README #2). No bridge schema change (see §5).

## 5. Data & schema changes

**Settings (SharedPreferences, the `settings_repository.dart` pattern):**
- Add `settings.hrv_readiness_enabled` (bool, default **false** — opt-in even for paid users; the lifter turns it on). Mirror the `_kLiveActivity` / `settings.live_activity` key + `AppSettings` field + `SettingsNotifier` writer pattern in `lib/core/settings/settings_repository.dart` and `lib/core/settings/settings_provider.dart`.

**DB schema (cumulative migration, `lib/core/db/migrations.dart`; bump `_dbVersion` in `lib/core/db/database.dart` from 6 → 7):**
- Add a nullable column to `workout_sessions` (or the session-overrides table) recording the per-session decision so resume/watch-resync don't re-prompt and the modifier is reproducible:
  - `hrv_decision TEXT` — `NULL` (not shown) | `'accepted'` | `'ignored'`.
  - `hrv_today_ms REAL`, `hrv_baseline_ms REAL`, `hrv_drop_pct REAL` — the snapshot of what the card showed (so the decision is auditable and the modifier deterministic across resume; no re-query of HealthKit on resume).
- Follow the existing additive pattern: append a `schemaV7Up` const list of `ALTER TABLE` statements to `migrations.dart` and wire it into the `onUpgrade` ladder in `database.dart` (mirroring how `schemaV6Up` was added). No table drops, no data rewrites — append-only, consistent with the reliability pillar.

**Watch bridge / Pigeon contract:** **No change.** HRV is read and the modifier applied on the phone *before* the snapshot is built; the watch only ever sees the resulting suggestions through the existing `WatchSessionSnapshot`. Do not add HRV fields to `pigeons/watch_bridge.dart`.

**HealthKit authorization additions:**
- **Read type to request:** `HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)` (read-only; we never write HRV).
- **Info.plist usage strings (phone `ios/Runner/Info.plist`):** the phone currently has no HealthKit usage strings (`WorkoutSessionManager.swift` notes that calling `requestAuthorization` without them is a hard precondition failure that *terminates the app*). Add:
  - `NSHealthShareUsageDescription` → e.g. *"LS Gym Track reads your overnight heart-rate variability to suggest one optional adjustment to today's top set. Your health data never leaves your device."*
  - (No `NSHealthUpdateUsageDescription` needed on the phone unless we later write workouts there — v1 is read-only.)
- **Entitlement:** add the HealthKit capability to the **Runner** (phone) target. The watch target already has it (`devAssets/SOW_WATCH_COMPANION.md` §9.3).
- **Gate, mirroring the watch:** replicate the `healthKitUsageDescribed` guard from `WorkoutSessionManager.swift` on the phone side — never call `requestAuthorization` unless both the usage string is present and `HKHealthStore.isHealthDataAvailable()` is true.

## 6. Implementation plan

Ordered by layer. New files namespaced under `lib/features/readiness/` (a sibling feature, so the workout feature stays lean).

1. **domain/** — `lib/features/readiness/domain/hrv_readiness.dart`:
   - `HrvReading { DateTime day; double sdnnMs; }`
   - `ReadinessResult { double todayMs; double baselineMs; double dropPct; bool triggered; double softenFraction; int rirFloor; }`
   - Pure function `computeReadiness(List<HrvReading> last7, HrvReading today)` implementing the pseudocode below — **no I/O**, fully unit-testable (mirrors the pure `cursorAfter` / `insertOrderPosAfter` style in `active_workout_controller.dart`).

2. **Native HealthKit read (Swift, Runner target)** — a small Pigeon HostApi method or a one-off method channel on the phone, e.g. `HealthKitHrvHostApi.recentHrvSamples(daysBack: 8) -> List<HrvSample>`:
   - Implemented in `ios/Runner/` next to `WCSessionManager.swift`, defensively guarded (`isHealthDataAvailable` + usage-string check + `try?`), running an `HKSampleQuery` for `.heartRateVariabilitySDNN` over the last ~8 days, returning `(startDate, sdnnMs)` tuples. Reuse the graceful-degrade discipline of `WorkoutSessionManager.swift`.
   - If extended via Pigeon, add a new `@HostApi` to `pigeons/watch_bridge.dart` (or a new `pigeons/healthkit_bridge.dart`) and regenerate — but it stays **phone-only**, no watch counterpart.

3. **data/** — `lib/features/readiness/data/hrv_repository.dart`: calls the native read, buckets samples into per-day means (today + trailing 7), returns `List<HrvReading>`. All errors → empty list (no-op).

4. **application/** — `lib/features/readiness/application/readiness_controller.dart`:
   - `readinessProvider` (FutureProvider/family on sessionId): gated by `settings.hrv_readiness_enabled` AND the SOW-06 `proEntitlementProvider`; off → returns `null` (no card). On → reads HRV via the repository, runs `computeReadiness`, persists the snapshot + `hrv_decision = NULL` via the workout DAO, returns `ReadinessResult` when `triggered`.
   - Acceptance API: `accept(sessionId)` / `ignore(sessionId)` write `hrv_decision` and, on accept, set the session's `hrvModifier` consumed by the SOW-07 suggestion layer.

5. **SOW-07 integration point** — in the SOW-07 suggestion provider/controller: read the active session's `hrvModifier` (absent unless accepted) and apply the bounded load-soften + RIR-floor cap from decision 4 *after* SOW-07 computes its raw suggestion, *before* it's surfaced/pushed to the watch.

6. **presentation/** — `lib/features/readiness/presentation/readiness_card.dart`: the card (ASCII mock above), shown once from `active_workout_screen.dart` when `readinessProvider` returns a triggered result and `hrv_decision == NULL`. Accept/Ignore buttons call the controller. Plus a settings toggle row (paid-gated) in the existing settings screen.

7. **Migration + Info.plist + entitlement** — `schemaV7Up` in `migrations.dart`, bump `_dbVersion` to 7 in `database.dart`, add `NSHealthShareUsageDescription` + HealthKit capability to the Runner target.

**Readiness computation (pseudocode):**

```
computeReadiness(last7: List<HrvReading>, today: HrvReading) -> ReadinessResult:
    DROP_THRESHOLD = 0.10        # 10% below baseline triggers
    MAX_SOFTEN     = 0.10        # never soften load more than 10%
    RIR_FLOOR_CAP  = 2           # never push RIR floor below 2

    valid = [r for r in last7 if r is not null]        # decision 7
    if len(valid) < 4 or today is null:
        return ReadinessResult(triggered = false)      # silent no-op

    baseline = mean(r.sdnnMs for r in valid)           # 7-day rolling mean (today excluded)
    if baseline <= 0:
        return ReadinessResult(triggered = false)

    dropPct = (baseline - today.sdnnMs) / baseline      # >0 means today is below baseline

    if dropPct < DROP_THRESHOLD:
        return ReadinessResult(triggered = false)       # within normal band OR above baseline → no card

    # Bounded, downside-only adjustment. Scale softening with the drop but hard-cap it.
    softenFraction = min(MAX_SOFTEN, dropPct - DROP_THRESHOLD + 0.05)   # ramps in, capped at 10%
    softenFraction = clamp(softenFraction, 0.0, MAX_SOFTEN)

    return ReadinessResult(
        triggered      = true,
        todayMs        = today.sdnnMs,
        baselineMs     = baseline,
        dropPct        = dropPct,
        softenFraction = softenFraction,   # applied to SOW-07 top-set load
        rirFloor       = RIR_FLOOR_CAP     # effectiveRirFloor = max(sow07Floor, 2)
    )
```

## 7. Acceptance criteria

- [ ] Paid user, HRV ≥10% below 7-day baseline, ≥4/7 days of data, first session of the day → exactly **one** Readiness card appears before the first set logger.
- [ ] Card shows the plain-language drop line, the bounded suggestion (load ≤10% soften and/or RIR floor capped at 2), and an honest "ignore and train as planned" option.
- [ ] **Accept** applies the bounded modifier to this session's SOW-07 suggestions (load re-rounded to `weightStepKg`; RIR floor = max(sow07Floor, 2)); **Ignore** leaves SOW-07 suggestions un-modified.
- [ ] Load softening **never exceeds 10%**; RIR floor cap **never below 2**; the modifier **never raises** intensity on a good-HRV day; the card **never auto-applies**.
- [ ] Card fires **at most once per calendar day**; resuming the session or opening it on the watch does **not** re-prompt (decision persisted as `hrv_decision`).
- [ ] **Free** user: feature fully invisible — no HealthKit HRV prompt, no settings toggle effect, no card.
- [ ] HealthKit unavailable / unauthorized / no today sample / <4 days of data → **silent no-op**, workout starts exactly as today, no crash, no error toast.
- [ ] Watch receives the (possibly modified) suggestions through the existing snapshot; **no** HRV field added to the Pigeon contract; the watch shows no readiness UI.
- [ ] DB migrates v6 → v7 cleanly with no data loss; HRV columns are nullable and absent on un-prompted sessions.

## 8. Testing

**Unit (in-memory sqflite via `sqflite_ffi`, mirroring `test/dao_test.dart` / `test/queries_test.dart` / `test/workout_progress_test.dart`):**
- `computeReadiness` table-driven cases: above baseline → no trigger; exactly 10% drop → boundary; 18% drop → trigger + softenFraction capped at 10%; 40% drop → still capped at 10% (no runaway); <4 valid days → no trigger; today null → no trigger; baseline 0 → no trigger.
- DAO: `hrv_decision` / snapshot columns persist and survive a resume reconciliation; un-prompted sessions have `NULL`. Add a v6→v7 migration test (mirror existing migration assertions).
- SOW-07 integration: with `hrvModifier` present, the suggestion's top-set load is softened + re-rounded and the RIR floor is raised; without it, the suggestion is byte-identical to un-modified SOW-07.

**Widget:**
- Readiness card renders the right copy for a given `ReadinessResult`; Accept/Ignore call the controller; card does not appear when entitlement is off or `triggered == false`.

**HealthKit sandbox / simulated HRV (manual matrix — needs the simulator's Health app or a paired device):**
- Seed `heartRateVariabilitySDNN` samples in the iOS Simulator's Health app (or via a debug seeding path) to fabricate a baseline + a low-today reading; confirm the card triggers.
- Authorization denied → no-op. Authorization granted, no overnight sample → no-op.
- Real paired-device sign-off: confirm overnight watch-recorded HRV is readable on the phone the next morning (the cross-device path the watch companion already relies on for HK fidelity — `devAssets/SOW_WATCH_COMPANION.md` §11 notes HK fidelity needs real paired devices for final sign-off).

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **HRV noise** — single-night SDNN is volatile; one bad reading could fire a spurious nudge | High | Require ≥4/7 days of data (decision 7); trigger only on a ≥10% drop; cap the adjustment at 10% load / RIR floor 2; downside-only (no upside overreach nudge). Surface the *baseline comparison*, not a raw number, so a single odd night is contextualized. |
| **Over-reach into "coaching"** — the readiness card creeps toward a recovery dashboard / daily score (Risk #4, the minimalism trap) | Medium | Hard guardrail in the SOW: one card, once, pre-workout, accept/ignore. No score, no chart, no history surface. Any future multi-signal/score work is a *new* SOW with its own minimalism review, not a v1 expansion. |
| **Privacy** — HRV is sensitive health data | Medium | Read-only, on-device, never transmitted (HealthKit data stays in the local store; nothing in the bridge or any backend). Honest usage string ("never leaves your device"). No write-back, no analytics on HRV. |
| **Apple ships an AI health coach** → this becomes table-stakes, eroding the differentiator | Medium | Accept it as a *trigger to accelerate* (decision 3 triggers), not a reason to over-build. Shipping the minimalist version first still wins the trust-wary indie filter. |
| **Low value if recovery-aware programming doesn't pull** (Hevy Trainer adoption low) | Medium | Phase-3, conditional. The defer trigger (decision 3) lets us hold without sunk cost; the feature is opt-in and additive, so a low-uptake launch costs nothing in core trust. |
| **Phone target gains HealthKit for the first time** — auth-prompt termination if Info.plist misconfigured | Low | Replicate the proven `healthKitUsageDescribed` + `isHealthDataAvailable()` gate from `WorkoutSessionManager.swift`; never call `requestAuthorization` without the usage string present. |

## 10. Definition of done

- **Shippable bar:** a paid lifter with a low-HRV morning sees one honest, bounded, ignorable card before training that can nudge the SOW-07 suggestion down — and a free lifter, an un-authorized lifter, or a lifter without enough data sees nothing different from today. No crash, no dashboard, no auto-apply.
- **Positioning claim unlocked:** *"Recovery-aware programming — one honest nudge when your HRV says back off — on a minimalist logger, at a one-time price."* The unoccupied future lane from [00-competitive-analysis.md](../00-competitive-analysis.md), shipped before Apple normalizes it.
- **Roadmap update:** flip SOW-09 in [02-roadmap.md](../02-roadmap.md) from ⬜ Not started → 🟦/✅ as it progresses; record whether an accelerate/defer trigger fired (Apple AI coach / Hevy Trainer adoption) in the Decision-condition triggers section.
