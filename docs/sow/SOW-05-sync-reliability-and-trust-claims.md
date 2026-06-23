# SOW-05 — Sync Reliability Hardening & Trust Claims

> **Status:** ⬜ Not started · **Phase:** 1 · **Tier:** Free
> **Owner:** berke · **Est. size:** M
> **Strategic rationale:** Proves the append-only, phone-as-source-of-truth, idempotent-merge watch sync structurally *cannot* reproduce Strong's signature data-loss bug — turning it into the testable App Store claim "Your phone is always the source of truth — the watch never overwrites it." Underwrites the entire trust pillar. See [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) (trust pillar + risk 5) and [00-competitive-analysis.md](../00-competitive-analysis.md) ("Reliability as a claim").

This SOW is **hardening + a test plan + a marketing claim**, NOT a rebuild. The watch sync already exists (schema v3). The reconciliation design of record is [`devAssets/SOW_WATCH_COMPANION.md`](../../devAssets/SOW_WATCH_COMPANION.md) §6; this document treats those invariants as testable rules, enumerates every concurrent-edit / out-of-order / offline-replay / dropped-message edge case, builds the deterministic test suite that proves them, fixes whatever the audit surfaces, and gates the claim behind that suite before every release.

---

## 1. Goal & Constraints

- **What this delivers:**
  - A proven, regression-protected guarantee that **the watch never overwrites or deletes data on the phone** — sets are append-only and keyed by a caller-supplied UUID; edits/cursor/rest are last-writer-wins; finish/discard are terminal-first-wins; merges are idempotent.
  - The testable App Store / marketing claim **"Your phone is always the source of truth — the watch never overwrites it,"** with a release-gate checklist QA runs before shipping it.
  - Any small hardening fixes the audit surfaces (already-identified candidate: LWW timestamp guards on `editSet`/`deleteSet`).
- **Why now:** Strong's #1 reputational wound is its Apple Watch overwriting the phone with older data and *deleting workouts* — a persistent complaint with [its own Strong help article](#). Our sync structurally cannot do this, but the *claim* is only safe if the implementation is provably correct. Per strategy risk 5, "the whole trust pillar evaporates if we ship our own data-loss bug." This SOW is the proof.
- **Hard constraints:**
  - **Free, forever.** Reliability is table stakes, never a paid tier.
  - **No rebuild.** The append-only + LWW + terminal-wins model in `SOW_WATCH_COMPANION.md` §6 is the source of truth; we harden and prove it, we do not redesign it.
  - **No new runtime dependency.** Tests use `sqflite_common_ffi` (already a dev-dependency, see `test/dao_test.dart`); Pigeon stays a build-time-only codegen.
  - **Minimalism guardrail.** Hardening fixes must be surgical (timestamp guards, idempotency assertions), not new sync machinery.
- **Non-goals:**
  - No change to the wire contract, the three WC channels, or the Pigeon schema (`pigeons/watch_bridge.dart`). Schema stays v3.
  - No multi-watch / multi-phone / cloud-sync support (single phone is the permanent store, full stop).
  - No automation of the **real-device** paired matrix — `WCSession` background delivery + HealthKit fidelity require real hardware and stay a *manual* gate (mirrors `SOW_WATCH_COMPANION.md` §15).
  - No new conflict-resolution policy. We test the policy that exists; we do not invent CRDTs or vector clocks.

## 2. Competitive context

| Rival | Watch sync posture | Our edge |
|---|---|---|
| **Strong** | Watch can overwrite the phone with older data and delete workouts; documented, persistent complaint; sync is the brand's open wound. | Our model has no "watch writes authoritative state to phone" path at all. The phone's sqflite is the only permanent store; the watch's events are *appended and merged*, never blindly applied. |
| **Hevy** | Cloud-first, server reconciles; robust but the watch is a thin Wear OS mirror. | We don't need a server to be safe — the phone is the authority and offline-correct. |
| **Setgraph / GymStreak** | Watch-strong but no published reliability claim; sync correctness is invisible to the user. | We turn correctness into an *explicit, marketed, QA-gated* promise — a trust signal no rival makes. |

**What "match" looks like:** never lose or corrupt a logged set under any concurrent-edit / offline / dropped-message scenario. **What "surpass" looks like:** make the guarantee a *public claim* backed by a deterministic test suite and a per-release verification gate — converting an invisible engineering property into a marketed differentiator the incumbents cannot credibly copy (they carry betrayal records; we do not).

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Source of truth | **Phone sqflite is the only permanent store.** The watch is a live driver; it never holds authoritative state. | Structurally forecloses Strong's failure mode. |
| 2 | Set log model | **Append-only, keyed by caller-supplied UUID** (`WatchSet.id`). Insert-if-unseen; re-delivery is a no-op. | Idempotent under re-delivery on both WC channels; a set is never double-counted or lost. |
| 3 | Edit / cursor / rest | **Last-writer-wins by `timestampMs`.** | Deterministic convergence without a coordinator. |
| 4 | Finish / discard | **Terminal, first-wins by `sessionId`** — later events for a terminated session are ignored. | A late watch set can never resurrect or mutate a finished workout. |
| 5 | Snapshot application | **A merge keyed by `set.id`, never a clobber.** A received snapshot never deletes a set the receiver logged that isn't in it yet. | The "snapshot" path can't become an overwrite path. |
| 6 | Mutation dedupe | **By `deviceId:seq`** on the phone (bounded ledger), and **by `set.id`** in the controllers. | Two independent dedupe layers: transport-level (the same mutation on both channels) and domain-level (idempotent apply). |
| 7 | Watch seq seeding | **Seeded from wall-clock ms, monotonic across watch app launches.** | A 0-based counter would reset on relaunch and collide with seqs the phone already saw → silent set loss. Already implemented; this SOW *locks it under test*. |
| 8 | Audit fix scope | **Add LWW timestamp guards to phone-side `editSet`/`deleteSet`** so a late-arriving stale edit cannot clobber a newer one. | Closes the one place the current controller applies a remote mutation *unconditionally* (see §5, item H1). |
| 9 | Claim gate | **The marketing claim ships only when the §8 unit suite is green AND the §8 manual matrix is signed off for the release.** | The claim is a liability if untested; the gate makes it safe. |

## 4. Design & UX

No user-facing screen changes. This SOW operates entirely at the reconciliation + test layer. Two surfaces are *touched indirectly*:

- **App Store listing copy** (not code): adds the claim line. Phrasing locked in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md): *"Your phone is always the source of truth — the watch never overwrites it."*
- **The existing ⌚ indicator** in `active_workout_screen.dart` (`SOW_WATCH_COMPANION.md` §10) is unchanged; it remains the only visible "watch is driving" affordance.

Watch behavior is unchanged. The watch stays optimistic (renders its own action instantly) and durable (queues via `transferUserInfo`); this SOW only *proves* the phone-side reconciliation of those events is correct.

## 5. Reconciliation invariants — restated as testable rules

These are the §6 rules of `SOW_WATCH_COMPANION.md` rewritten as assertions a test can check. Each is tagged so §8 can reference it.

| Rule | Invariant (must always hold) | Where enforced |
|---|---|---|
| **R1 — Append-only** | Applying `logSet(s)` twice yields exactly one set with `id == s.id`. Re-delivery is a no-op. | `ActiveWorkoutController.applyWatchLogSet` (dedupe by `id`, `active_workout_controller.dart:340`) |
| **R2 — Identity attribution** | A logged set is attributed to `set.exerciseId`, not the cursor's exercise — so a drop set's drops, arriving after the cursor advanced, still land on the right exercise. | `applyWatchLogSet` (`active_workout_controller.dart:348`) |
| **R3 — Forward-only cursor** | `logSet`/`applyWatchLogSet`/`gotoExercise` never *rewind* the workout's progress; the cursor advances only when the current exercise meets its target in distinct groups. | `applyWatchLogSet` advance block (`active_workout_controller.dart:369`), `goToExerciseIndex` (`active_workout_controller.dart:418`) |
| **R4 — Edit LWW** | An `editSet` applies iff its `timestampMs` is ≥ the target set's last-known edit time; an older edit is ignored. | `editSet` — **GAP, see H1** (`active_workout_controller.dart:385`) |
| **R5 — Delete LWW / tombstone** | A `deleteSet` wins over an older edit; it is ignored if a newer edit for that id exists. Re-applying a delete is a no-op. | `deleteSet` — **GAP, see H1** (`active_workout_controller.dart:398`) |
| **R6 — Cursor LWW + skip-safe** | `gotoExercise` never lands on a skipped slot (falls forward); latest intent wins. | `goToExerciseIndex` (`active_workout_controller.dart:418`) |
| **R7 — Rest LWW** | `restSet` (start/adjust/cancel) is pure LWW on `restEndsAtMs`; `0` means cancel; an expired `endsAt` renders as "no rest". | `buildWatchSnapshot` (`watch_snapshot.dart:30`); watch `applyRemoteMutation .restSet` |
| **R8 — Terminal first-wins** | After `finish`/`discard` for a `sessionId`, every later event for that session is ignored on both devices. | Watch `terminatedSessionIds` (`WatchWorkoutModel.swift:162`); phone: a terminated session has `state == null`, so `applyWatchLogSet` early-returns (`active_workout_controller.dart:216`) |
| **R9 — Snapshot is a merge, never a clobber** | Applying a snapshot never deletes a locally-logged set absent from it; it unions by `set.id`. | Watch `mergeSnapshot` (`WatchWorkoutModel.swift:538`) |
| **R10 — Transport idempotency** | The same mutation delivered on both `transferUserInfo` and `sendMessage` is applied once. | Phone `markSeen` ledger keyed `deviceId:seq` (`WCSessionManager.swift:253`) |
| **R11 — Seq monotonicity** | The watch's `seq` is monotonic across app launches, so post-relaunch sets are never dropped as duplicates. | Watch `seq = nowMs()` seed (`WatchWorkoutModel.swift:180`) |
| **R12 — Snapshot is a pure projection** | `buildWatchSnapshot` is side-effect-free: it reads `ActiveSession` + rest + settings and emits a `WatchSessionSnapshot`; it never writes the DB. | `buildWatchSnapshot` (`watch_snapshot.dart:22`) |

### Hardening items the audit surfaces

- **H1 (locked, decision 8) — `editSet`/`deleteSet` apply unconditionally.** Today `ActiveWorkoutController.editSet` (`active_workout_controller.dart:385`) and `deleteSet` (`:398`) write through to the DAO and in-memory state with **no `timestampMs` comparison**. R4/R5 are therefore *not* enforced on the phone: a stale watch edit arriving after a newer phone edit would clobber it (a small, bounded data-quality bug — not data *loss*, since the set still exists, but it violates the stated LWW rule). Fix: thread the originating `timestampMs` through these paths and apply only when not older than the set's last-known mutation time. This requires either (a) tracking a per-set last-mutation timestamp, or (b) — simpler, minimalism-preferred — comparing against the set's `loggedAt`/existing edit time already in `WorkoutSet`. Pick (b) if `WorkoutSet` carries enough; otherwise add a single `lastEditedAtMs` column under a v7 migration (see §5 schema note).
- **H2 (verify, likely no-op) — terminal guard on inbound watch sets.** Confirm that once a session is finished on the phone (`state == null`), a late `applyWatchLogSet` cannot start/insert anything. The early `if (current == null ...) return;` at `active_workout_controller.dart:216` already does this; H2 is a test to *lock* it (R8), not a code change.
- **H3 (verify) — dedupe ledger eviction safety.** The phone's `seenMutationKeys` ledger is bounded to 512 (`WCSessionManager.swift:58`). Confirm that eviction cannot cause a *replayed, evicted* mutation to be re-applied destructively. Because the controllers are *also* idempotent (R1 by `id`, R8 by terminal state), an evicted-then-replayed `logSet` is still a no-op — but a replayed `editSet`/`deleteSet` is only safe once H1 lands. H3 is the test that ties the two dedupe layers together.

## 6. Data & schema changes

**Default: No schema change.** The hardening is logic-only if H1 can compare against a timestamp already on `WorkoutSet` (its `loggedAt`, or an existing edit field).

**Conditional (only if H1 needs a tiebreaker the row doesn't already carry):** add `last_edited_at_ms INTEGER` to `workout_sets` via a **v7 migration**, mirroring the cumulative additive pattern in `lib/core/db/migrations.dart` (each `schemaVNUp` is a list of additive statements; bump `version` in `lib/core/db/database.dart`; extend the `onCreate` batch in `test/dao_test.dart` with a `schemaV7Up` loop). The column defaults to the row's `logged_at` for existing rows so LWW has a baseline. **Decide during the audit, not up front** — prefer the no-migration path.

**Bridge / Pigeon:** no change. `WatchMutation` already carries `timestampMs` (`watch_bridge.g.dart:447`); H1 consumes a field that already crosses the wire. The snapshot schema stays v3 (`watch_snapshot.dart:15`).

**Settings:** no new flag. `watchSyncEnabled` / `liveActivityEnabled` are out of scope here.

## 7. Acceptance criteria

- [ ] **Every rule R1–R12 has at least one passing unit test** in the new `test/watch_reconciliation_test.dart`, run against in-memory `sqflite` (mirrors `test/dao_test.dart`).
- [ ] **R1 proven:** applying the same `logSet` mutation N times (both channels, plus a snapshot echo) yields exactly one set; the count never grows and never drops.
- [ ] **R8 proven:** a `logSet`/`editSet`/`deleteSet` arriving *after* `finish`/`discard` for that session is a no-op on the phone (the completed session is untouched).
- [ ] **R9 proven:** a snapshot missing a set the receiver just logged does NOT delete that set (union-by-id holds).
- [ ] **H1 fixed:** `editSet`/`deleteSet` enforce LWW by `timestampMs`; a stale edit is dropped; the suite has a regression test for it. (If H1 resolves to "the existing field suffices," that decision is recorded in the test's doc comment.)
- [ ] **The "no overwrite / no delete from watch" property is expressed as a single high-level test** ("watch can never reduce the phone's set count for a finished or in-progress session") — the executable form of the marketing claim.
- [ ] **The manual paired-device matrix (§8) is documented as a checklist** and run once on real paired hardware, with results recorded.
- [ ] **The release-gate checklist (§8) is added** and references the unit suite + manual matrix as preconditions for shipping the claim.
- [ ] **No regression:** existing `flutter test` (`dao_test`, `queries_test`, `workout_progress_test`) stays green; phone-only behavior with no watch paired is unchanged.

## 8. Testing

### 8.1 Unit tests — deterministic, in-memory `sqflite`

New file: `test/watch_reconciliation_test.dart`, built on the `_openInMemory()` + `sqfliteFfiInit()` harness from `test/dao_test.dart`. Tests drive `ActiveWorkoutController` (or, where a controller needs a `ProviderContainer`, a thin harness around it) and the pure builders directly. Pure functions (`buildWatchSnapshot`, `cursorAfter`, `insertOrderPosAfter`) are tested without a DB.

**Edge-case → expected-outcome matrix** (each row is a unit test; tags map to §5 rules):

| # | Scenario | Inbound sequence | Expected idempotent outcome | Rule |
|---|---|---|---|---|
| U1 | Set re-delivered on both channels | `logSet(id=A)` applied twice | exactly one set `A`; cursor advances once | R1, R10 |
| U2 | Snapshot echoes an already-applied set | `logSet(A)` then snapshot containing `A` | still one `A`; no duplicate | R1, R9 |
| U3 | Drop-set drops arrive after cursor advanced | `logSet(top, ex=X)`, cursor → ex Y, then `logSet(drop, ex=X)` | drop lands on X (not Y); X's group count correct | R2 |
| U4 | Out-of-order seq | `logSet(A, seq=5)` then `logSet(B, seq=3)` | both A and B present (append-only doesn't depend on order) | R1, R3 |
| U5 | Stale edit after newer edit | `editSet(A, ts=100)` then `editSet(A, ts=50)` | A reflects the ts=100 value; the ts=50 edit is dropped | R4, H1 |
| U6 | Delete vs older edit | `editSet(A, ts=50)` then `deleteSet(A, ts=100)` | A is gone | R5 |
| U7 | Edit after delete (tombstone) | `deleteSet(A, ts=100)` then `editSet(A, ts=50)` | A stays deleted (no resurrection) | R5 |
| U8 | Re-applied delete | `deleteSet(A)` twice | no-op the second time; no crash | R5 |
| U9 | Late set after finish | `finish(session)` then `logSet(A)` | A is NOT inserted; finished session unchanged | R8 |
| U10 | Late edit/delete after discard | `discard(session)` then `editSet/deleteSet` | no-op; discarded session unchanged | R8 |
| U11 | Snapshot missing a freshly-logged set | local `logSet(A)`, then snapshot without A | A survives (union-by-id) | R9 |
| U12 | gotoExercise onto a skipped slot | skip slot i, then `gotoExercise(i)` | cursor falls forward to next non-skipped slot | R6 |
| U13 | gotoExercise never rewinds progress | cursor at exercise 3, `gotoExercise(1)` | navigation cursor moves but logged history/progress intact | R3, R6 |
| U14 | Rest LWW | `restSet(endsAt=T1)` then `restSet(endsAt=T2 > T1)` | snapshot rest = T2; cancel (`0`) wins last | R7 |
| U15 | Expired rest renders as none | snapshot with `restEndsAtMs` in the past | `buildWatchSnapshot` emits `restEndsAtMs == 0` | R7, R12 |
| U16 | Snapshot is a pure projection | call `buildWatchSnapshot` twice on same inputs | identical output; zero DB writes | R12 |
| U17 | **Claim test (umbrella)** | finish a session with N sets, then replay a full burst of stale watch events (log/edit/delete/finish) | the phone's persisted set count for that session is **never reduced and never corrupted**; session stays completed | R1, R5, R8, R9 |

> U17 is the executable form of the marketing claim and is the single test the release gate keys on. It asserts the property "**the watch can never overwrite or delete the phone's data**" directly.

Test conventions: follow `test/dao_test.dart` — `setUpAll(sqfliteFfiInit)`, open a fresh in-memory DB per test, `await db.close()` at the end, small `Future.delayed` only where wall-clock ordering matters (use explicit `timestampMs` values instead of sleeps wherever possible — these tests must be deterministic).

### 8.2 Manual paired-device matrix (real hardware — claim sign-off)

`WCSession` background delivery, `transferUserInfo` queueing while suspended, and HealthKit fidelity **cannot be simulated faithfully** (per `SOW_WATCH_COMPANION.md` §15). Run this once on real paired devices per release that ships or re-affirms the claim. Each cell's pass criterion: **after reconnect/resume, the phone's logged sets for the session are a superset of everything logged on either device, with zero duplicates, zero deletions, and the correct cursor.**

Matrix: **phone state × watch state × reachability.**

| | watch: idle | watch: active | watch: logging | watch: resting |
|---|---|---|---|---|
| **phone foreground, reachable** | trivial mirror | mirror live | set appears on phone instantly | rest countdown matches |
| **phone background, reachable** | — | mirror on resume | set queued, applied on resume, no dup | rest LWW on resume |
| **phone killed** | — | — | **set durably queued via `transferUserInfo`, applied on next launch, no loss** | rest state reconciles on launch |
| **reachability off → on** | resync on reconnect | snapshot merge, no clobber | **queued sets flush both ways, deduped** | rest LWW after flush |

Plus four **named adversarial runs** (the Strong-failure analogues):
1. **Offline burst then reconnect:** log 5 sets on the watch with the phone in airplane mode; reconnect; assert all 5 land once, none lost, none duplicated.
2. **Concurrent edit:** edit the same set on phone and watch within the same second; assert LWW by timestamp, no loss.
3. **Finish-then-late-set:** finish on the phone while a watch set is mid-flight; assert the late set does not resurrect or mutate the completed workout (R8).
4. **Relaunch mid-session:** force-quit the watch app after logging, relaunch, log again; assert seq monotonicity prevents the post-relaunch set from being dropped as a duplicate (R11).

### 8.3 Regression guard

Confirm phone-only behavior is byte-for-byte unchanged when `isPaired() == false` — no snapshot pushes, no overhead, existing tests green.

## 9. The marketing claim & release gate

**The claim (locked phrasing):** *"Your phone is always the source of truth — the watch never overwrites it."*

Permitted supporting line for the listing: *"Log on your wrist with the phone in your pocket — nothing is ever lost or overwritten."* Do **not** name competitors in the listing.

**Release-gate checklist — QA runs this before any build that ships or re-affirms the claim:**

- [ ] `flutter test test/watch_reconciliation_test.dart` is **green**, U1–U17 all passing.
- [ ] U17 (the umbrella claim test) specifically passes on the exact commit being shipped.
- [ ] Full `flutter test` suite green (no regression in `dao_test`/`queries_test`/`workout_progress_test`).
- [ ] If the watch sync code (`active_workout_controller.dart`, `watch_snapshot.dart`, `WCSessionManager.swift`, `WatchWorkoutModel.swift`, `pigeons/watch_bridge.dart`) changed since the last claim sign-off, the **§8.2 manual matrix + 4 adversarial runs** are re-run on real paired hardware and results recorded in the release notes.
- [ ] Snapshot `schemaVersion` and the Pigeon contract are unchanged, OR a contract change has its own reconciliation tests.
- [ ] The claim copy in the App Store listing matches the locked phrasing above.

If any box is unchecked, **the claim does not ship** (the build may still ship without the claim).

## 10. Implementation plan

Ordered, smallest-blast-radius first:

1. **Audit (no code):** walk R1–R12 against the four sync files; confirm which rules already hold and pin down H1's exact fix (timestamp source). Record findings in this SOW's §5.
2. **`domain/` (only if H1 needs it):** add `lastEditedAtMs` to `WorkoutSet` (`lib/features/workout/domain/workout_set.dart`) — *prefer to skip* if `loggedAt`/existing fields suffice.
3. **`data/` (only if step 2):** v7 migration in `lib/core/db/migrations.dart` (`schemaV7Up`), bump `version` in `lib/core/db/database.dart`, extend the `onCreate` batch in `test/dao_test.dart`.
4. **`application/` (the fix):** add LWW timestamp guards to `ActiveWorkoutController.editSet` / `deleteSet` (`active_workout_controller.dart:385`, `:398`) so a stale mutation is dropped. Thread `timestampMs` from `WatchMutation` through the `WatchBridgeFlutterApi` handler that maps mutations to controller calls.
5. **`test/`:** author `test/watch_reconciliation_test.dart` covering U1–U17.
6. **Docs:** add the release-gate checklist (this §9) to the team's release runbook; update [02-roadmap.md](../02-roadmap.md) to mark the reliability claim as test-backed and shippable.

No `presentation/` or Swift changes are expected unless the audit surfaces a watch-side hardening item (e.g., a `mergeSnapshot` edge in `WatchWorkoutModel.swift:538`); if so, it gets its own row in §5 and a matching manual-matrix cell.

## 11. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| We ship the claim, then a real-device-only bug (background delivery / HealthKit) causes data loss → positioning collapses (strategy risk 5). | Medium | The claim is gated on the §8.2 **real-hardware** matrix, not just unit tests. The claim never ships on simulator evidence alone. |
| H1 fix needs a schema change that breaks an in-flight migration. | Low | Prefer the no-migration path; if a column is needed, it's additive (v7) and defaults from `logged_at`, matching the proven cumulative pattern. |
| LWW timestamp guard introduces a *new* way to lose an edit (over-aggressive drop). | Low | U5–U7 + U17 lock the exact behavior; "drop older edit" is data-quality, never data-loss (the set still exists). |
| Unit suite proves the merge logic but not the *transport*, giving false confidence. | Medium | The release gate requires the manual matrix whenever sync code changes; the unit suite is necessary, not sufficient, and the checklist says so. |
| Future schema/contract drift silently breaks reconciliation. | Medium | `schemaVersion` gate (`watch_snapshot.dart:15`) + a release-gate box that forces new reconciliation tests on any contract change. |
| The dedupe ledger (512) evicts and a replayed mutation re-applies. | Low | H3 test ties the two dedupe layers (transport `deviceId:seq` + domain `set.id`/terminal) so an evicted replay is still idempotent. |

## 12. Definition of done

- R1–R12 each have a green unit test in `test/watch_reconciliation_test.dart`; U17 passes on the shipped commit; full `flutter test` green.
- H1 is fixed (or explicitly recorded as a no-op with the existing field documented as the tiebreaker); H2/H3 verified by test.
- The §8.2 manual paired-device matrix + 4 adversarial runs have been executed once on real hardware with results recorded.
- The §9 release-gate checklist is in the release runbook and was followed for the build that first ships the claim.
- **Positioning unlocked:** the App Store claim *"Your phone is always the source of truth — the watch never overwrites it"* is live, test-backed, and listed in [02-roadmap.md](../02-roadmap.md) as a shipped trust differentiator. This SOW is the concrete discharge of strategy risk 5 and the "Reliability as a claim" line in [00-competitive-analysis.md](../00-competitive-analysis.md).
