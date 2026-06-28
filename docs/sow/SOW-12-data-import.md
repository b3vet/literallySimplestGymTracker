# SOW-12 — Data Import / Restore (JSON round-trip)

> **Status:** ⬜ Not started (committed NEXT block, after [SOW-02](SOW-02-data-export.md) + [SOW-02b](SOW-02b-workout-summary-share.md)) · **Phase:** 0/1 · **Tier:** Free
> **Owner:** berke · **Est. size:** L
> **Strategic rationale:** "Exporting means nothing without being able to import it somewhere else" (owner, 2026-06-23). Import completes the **data-ownership / trust** promise (you can leave *and* come back) and de-risks device migration. Consumes the import-ready JSON that [SOW-02](SOW-02-data-export.md) emits.

Follows the [SOW-00 template](SOW-00-template.md). This is a **WRITE path** — the only SOW in the portability cluster that can corrupt real data — so it gets its own careful spec and is sequenced *after* export ships.

---

## 1. Goal & Constraints
- **Delivers:** import a `ls-gym-track-export` JSON (schema `version: 1`) back into the app — restoring programs, sessions, and logged sets — via the share sheet / Files picker, with a **preview-then-confirm** flow and a **transactional, idempotent** write.
- **Hard constraints:** **Never corrupt or silently lose existing data.** Idempotent (re-importing the same file does not duplicate). Transactional (all-or-nothing). Schema-validated (reject/НЕ-partially-apply malformed or future-version files). Free. Phone-only.
- **Non-goals:** no cloud sync; no CSV import (JSON is the round-trip format); no automatic background restore; no merge UI conflict editor in v1 (pick one policy — see decision #1).

## 2. Competitive context
Most rivals offer export but **not** a clean local import (they assume cloud accounts). A trustworthy local import is a genuine differentiator for a no-account app and reinforces "your data is yours."

## 3. Locked decisions — **TO BE MADE WITH OWNER WHEN THIS SOW STARTS**
| # | Decision | Options (decide at build time) |
|---|----------|--------|
| 1 | **Import policy** | **(a) Merge/dedup** by stable id (skip rows already present — true round-trip, additive) · **(b) Replace-all** (wipe then restore — clean device-migration) · **(c) Both, user picks**. Leaning (a) as default + (b) behind a clear "replace everything" confirm. The export's stable ids make (a) feasible. |
| 2 | Conflict on same id, different data | keep-existing vs overwrite vs newest-wins (LWW by timestamp). |
| 3 | Schema mismatch | reject unknown/newer `version` with a clear message; never partially apply. |
| 4 | Entry point | Settings → DATA → "Import data" (Files picker), and/or "open .json with LS". |

## 4. Design & UX (sketch)
Pick file → **validate + preview** ("This file has 142 sessions, 1,830 sets, 3 programs. 12 are already in your library." ) → confirm policy (merge / replace) → progress → result summary. Cancel at any point before commit is a no-op.

## 5. Data & schema changes
- Reuses SOW-02's `ExportBundle`/JSON shape as the import contract. May add an `import` settings flag or none. Likely **no new table**; writes via existing DAOs inside a single sqflite transaction. A DB migration is only needed if a provenance/`imported_at` column is wanted (decide at build).

## 6. Implementation plan (outline)
1. **domain:** reuse `export_models.dart`; add a parser + validator (`ImportValidator`) producing a typed `ImportPlan` (counts, duplicates, conflicts) without writing.
2. **application:** `import_controller` — file pick (native bridge or `file_picker`-free channel), parse, validate, preview, then a **transactional** apply via DAOs (`db.transaction`), idempotent on ids.
3. **presentation:** Settings → Import row → preview sheet → confirm.
4. **Tests (critical):** round-trip (export → import into an empty DB → identical), idempotency (import twice → no dups), malformed/forged JSON rejected with no writes, partial-failure rolls back (transaction), merge vs replace semantics.

## 7. Acceptance criteria
- [ ] Round-trips an export with zero data change (export → wipe → import → identical history).
- [ ] Re-importing the same file produces **no duplicates** (idempotent).
- [ ] Malformed / wrong-version JSON is rejected with a clear message and **zero** writes.
- [ ] A mid-import failure leaves the DB exactly as before (transactional).
- [ ] Preview shows accurate counts before any write; cancel is a no-op.
- [ ] Existing data is never silently lost (replace-all requires an explicit confirm).

## 8. Testing
Heavy DAO/transaction tests in-memory (`sqflite_ffi`): round-trip identity, idempotency, rollback on injected failure, dedup-by-id, schema-version rejection, conflict policy. Manual: real export from a populated device imported into a fresh install.

## 9. Risks & mitigations
| Risk | Likelihood | Mitigation |
|---|---|---|
| Data loss / corruption on import | **High impact** | Transactional all-or-nothing; preview-then-confirm; idempotent ids; never auto-apply; extensive rollback tests. |
| Forged/malicious JSON | Med | Strict schema validation before any write; bounded sizes; no code-eval. |
| Merge ambiguity | Med | Default to additive merge-by-id; replace-all only behind explicit confirm. |

## 10. Definition of done
- **Shippable bar:** export→import round-trips losslessly and idempotently; malformed input is safely rejected; failures roll back; preview-then-confirm; §8 transaction tests green.
- **Trust unlocked:** the data-ownership promise is complete — leave and come back. Mark done in [02-roadmap.md](../02-roadmap.md).
