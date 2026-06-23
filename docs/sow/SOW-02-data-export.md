# SOW-02 — Data Export (CSV + JSON)

> **Status:** ⬜ Not started · **Phase:** 0 · **Tier:** Free
> **Owner:** berke · **Est. size:** S
> **Strategic rationale:** Closes the "Data export (CSV)" day-1 gap and makes "Your data exports any time" a *testable* trust claim — see [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) (trust pillar, free-tier table) and [00-competitive-analysis.md](../00-competitive-analysis.md) ("places we may be back" #2).

Every SOW in this folder follows this structure. Keep it grounded in real files (cite `lib/...` paths), match the existing architecture (Riverpod tri-layer, sqflite migrations, the design system), and respect the non-negotiables in [README.md](../README.md).

---

## 1. Goal & Constraints

- **What this delivers**
  - A single **"Export data"** action in Settings that serializes the user's **entire** workout history and hands it to the iOS share sheet as **two attachments**: a human-readable **CSV** (one row per logged set) and a portable **JSON** (nested sessions → sets, with units metadata).
  - The export is **complete** (all completed sessions, not one) and **free forever** — no gate, no count limit, no "Pro" tease.
  - Weights are emitted in **both** the user's display unit *and* kg, so the file is self-describing regardless of the kg/lb setting.

- **Why now**
  - Absence of CSV export is a documented **recommendation-stopper** on r/weightroom and a named gap (`00-competitive-analysis.md` #2). Strong's own users complain they "can export individual workouts but not the entire history" — exporting the *whole* history is the differentiated, weaponized version of this feature.
  - It is the cheapest concrete proof of the trust pillar ("no betrayal record", "your data is yours"). Trust is our single highest-leverage asset (`01-strategy-and-positioning.md`).

- **Hard constraints**
  - **Free forever.** Never moves behind the paid seam. (Locked in the strategy free-tier table: "Unlimited core logging + data export, forever".)
  - **Complete.** Full history in one file each, not per-session.
  - **Unit-honest.** Respects the kg/lb display setting *and* always includes raw kg.
  - **No PII beyond workout data.** No device IDs, no account data (there is no account), no analytics, no file paths embedded in content.
  - **Must not block the UI.** Serialization + file write run off the platform thread / are awaited asynchronously; the button shows a progress state and never janks the Settings list.
  - **Minimal dependency footprint.** One small, well-maintained dependency at most (see Locked decision #1).

- **Non-goals**
  - **No import** (round-trip restore is a separate, later SOW — JSON is designed to *enable* it, but import is out of scope here).
  - **No cloud / iCloud sync, no email automation** — share sheet only; the user chooses the destination.
  - **No selective/date-range export, no per-session export** — one button, whole history. (Per-session export can come later; it's the *narrow* version Strong already has.)
  - **No PDF / pretty report.** CSV + JSON only.
  - **No watch entry point.** Export is a phone-only action (the phone is the source of truth).

## 2. Competitive context

| App | Export today | Where it falls short |
|---|---|---|
| **Strong** | CSV, but users report only **per-workout**, not the full history | The exact gap we exploit — we ship *entire history* in one tap |
| **Hevy** | CSV export of history (web + app) | Fine, but locked into Hevy's social/cloud model; we match on portability without the lock-in |
| **FitNotes** | CSV backup/export (Android heritage) | "Indestructible" but dated; no first-class iOS/watch story |
| **Alpha Progression / RP / Juggernaut** | Thin or absent | RIR-strong rivals under-invest here; export is not their pitch |

- **What "match" looks like:** a one-tap CSV of the complete history, openable in Excel/Sheets/Numbers.
- **What "surpass" looks like:** (a) complete history by default (beats Strong's per-workout limit), (b) a *second* machine-readable JSON with units metadata that makes the data trivially re-importable elsewhere, (c) dual-unit columns so the file is unambiguous, (d) it stays **free forever** while rivals trend toward gating backups behind Pro.

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Share mechanism | **Add `share_plus` (^11.x)** for the iOS share sheet; write temp files via the already-present `path_provider` (^2.1.5, `pubspec.yaml`). | The user prefers minimal/first-party deps, so this was weighed against rolling a native `UIActivityViewController` over a Pigeon/MethodChannel bridge. `share_plus` is a **flutter.dev-published, federated-plugin** package (the closest thing to first-party), is already the de-facto standard, and saves us hand-writing + maintaining Swift platform code plus a Pigeon contract for a one-shot feature. The bridge alternative is *more* surface area (Swift + `pigeons/`), not less. Net: one vetted dependency beats bespoke native glue. **Rejected:** custom native share bridge (maintenance cost, no payoff); writing to Documents dir + a "Files" prompt (worse UX, still needs a share entry point). |
| 2 | File formats | **Both CSV and JSON**, attached together in one share invocation. | CSV is human-readable (Excel/Sheets); JSON is portable/machine-readable and re-import-ready. Both is cheap once data is gathered once. |
| 3 | CSV granularity | **One row per logged set** (the `workout_sets` grain). | Matches the lowest atom of truth; aggregation is the consumer's job. Mirrors how `setsForSession` already returns rows (`workout_dao.dart:121`). |
| 4 | Weight columns | Emit **both** `weight_display` (+ `unit`) **and** `weight_kg`. | kg is the storage unit (`weight` column stores kg; `weight.dart` converts). Dual columns make the file self-describing and lossless. |
| 5 | Unit conversion | Reuse **`WeightConv.fromKg` / `format`** from `lib/core/util/weight.dart`. | Single source of truth for kg↔lb; no re-deriving the `2.2046226218` factor. |
| 6 | Session scope | **Completed sessions only** (`status = 'completed'`). | Matches history/stats semantics (`history_provider.dart`, `stats_provider.dart` both filter `completed`). Active/abandoned sessions are noise in an export. |
| 7 | Timestamps | **ISO-8601 UTC** strings in both formats (e.g. `2026-06-23T07:41:00.000Z`), derived from the stored epoch-ms. | Locale-independent, sortable, unambiguous. (`started_at`/`logged_at` are epoch-ms ints.) |
| 8 | Data layer | **Read-only aggregate** via a new method on `WorkoutDao` + name lookups via `ProgramDao`; **no new table, no migration.** | Export only reads; the data already exists. Keeps the DB at v6. |
| 9 | Filename | `ls-gym-track-export-YYYYMMDD-HHmmss.{csv,json}` | Sortable, app-branded, collision-free, no PII. |
| 10 | Empty history | Button stays enabled; export produces a **header-only CSV** + a JSON with `"sessions": []` and still shares. | Honest and non-surprising; proves the feature works even on a fresh install. |

## 4. Design & UX

A new **"DATA"** section in Settings, placed after **THEME** / **LOCK SCREEN** and before the dev-only **DEVELOPER** block (`settings_screen.dart`, the `ListView` children). One row, styled exactly like the existing `_ResetDataRow` / rest-timer card (`Material` + `InkWell` + bordered `Container`, `LsRadius.r3`, `LsType.displayM` title + `LsType.monoMeta` subtitle, trailing chevron).

```
┌─────────────────────────────────────────┐
│  DATA                                    │   ← EyebrowLabel
│ ┌─────────────────────────────────────┐ │
│ │ Export data                      ⤴  │ │   ← LsType.displayM + share glyph
│ │ ALL HISTORY · CSV + JSON            │ │   ← LsType.monoMeta, t.surface.text2
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Interaction flow:**

1. Tap **Export data** → row enters a busy state (swap trailing chevron for a small `CupertinoActivityIndicator`; disable re-tap while running). Subtitle flips to `PREPARING…`.
2. Controller gathers history off the UI thread, writes the two temp files, and invokes the share sheet.
3. iOS share sheet appears (Files, AirDrop, Messages, Mail, etc.). The two attachments are presented together.
4. On dismiss/complete: row returns to idle. On error: a one-line inline error (`LsSignals.danger`) + the row re-enables. No crash, no half-file shared.

**Design system tokens:** `LsType.displayM` / `LsType.monoMeta`, `LsSpace`/`LsGap.loose` spacing between sections, `LsRadius.r3`, `t.surface.*` colors, `LsSignals.danger` for the error state — all already in use in `settings_screen.dart`.

**Watch behavior:** None. Export is phone-only; the watch is never a source-of-truth surface.

## 5. Data & schema changes

**No schema change.** Export is purely read-only over existing tables (`workout_sessions`, `workout_sets`, `exercises`, `program_days`, `programs`). DB stays at **v6** (`lib/core/db/database.dart`).

- **Settings/flags:** none. No SharedPreferences key needed (it's a stateless action).
- **Watch bridge / Pigeon:** none (`pigeons/watch_bridge.dart` untouched).
- **New dependency:** `share_plus: ^11.0.0` added under `dependencies` in `pubspec.yaml` (next to `path_provider`). Run `flutter pub get`; iOS needs no extra `Info.plist` keys for outbound share.

## 6. Implementation plan

Ordered by layer. New files live under `lib/features/export/`.

**1. `data/` — aggregate read (DAO)**
- Add to `lib/features/workout/data/workout_dao.dart` a read-only method:
  ```dart
  /// All completed sessions with their sets, ordered oldest→newest, for export.
  Future<List<ExportSessionRow>> exportAllSessions() async { … }
  ```
  Single `rawQuery` joining `workout_sessions s` → `workout_sets w` (LEFT JOIN so empty sessions survive) → `exercises e` → `program_days d` → `programs p`, filtered `s.status = 'completed'`, ordered `s.started_at ASC, w.set_index ASC, w.logged_at ASC`. Returns flat rows the service groups by session. (Mirrors the join style already in `totalTonnageBySession` at `workout_dao.dart:226` and `overridesForSession` at `:370`.)

**2. `domain/` — export models**
- `lib/features/export/domain/export_models.dart`: plain immutable classes `ExportBundle { sessions, unit, generatedAt, appVersion }`, `ExportSession { id, startedAt, endedAt, programName?, dayName?, sets }`, `ExportSetRow { … }`. No Flutter imports (so it's unit-testable headless).

**3. `application/` — the serializer + controller**
- `lib/features/export/application/export_serializer.dart`: **pure, dependency-free** functions
  - `String toCsv(ExportBundle bundle)`
  - `Map<String, Object?> toJsonMap(ExportBundle bundle)` (+ `String toJsonString(...)` via `JsonEncoder.withIndent('  ')`).
  - CSV escaping handled here (quote any field containing `,`, `"`, `\n`; double internal quotes). This is the file the **unit test** targets.
- `lib/features/export/application/export_controller.dart`: a Riverpod `AsyncNotifier`/`Notifier` (e.g. `exportControllerProvider`) exposing `Future<void> exportAndShare()`:
  1. `ref.read(workoutDaoProvider).exportAllSessions()` (provider at `active_workout_controller.dart:73`).
  2. Read display unit from `settingsProvider`; read `appVersion` from `package`/`pubspec` (or hard-string for now).
  3. Build `ExportBundle`, call `toCsv` / `toJsonString`.
  4. Write both to temp files under `getTemporaryDirectory()` (`path_provider`) with the Locked-#9 filenames.
  5. `await SharePlus.instance.share(ShareParams(files: [XFile(csvPath), XFile(jsonPath)]))`.
  6. Drive a small `ExportState { idle, preparing, error(message) }` for the UI.
  - Heavy CSV/JSON string building can be wrapped in `compute()` if profiling shows jank, but a single user's history is small — await is sufficient; do **not** block `build`.

**4. `presentation/` — Settings entry**
- Modify `lib/features/settings/presentation/settings_screen.dart`: add a `_Section(title: 'DATA', child: _ExportRow(...))` before the `kDevToolsEnabled` block. `_ExportRow` watches `exportControllerProvider` for the busy/error state and calls `exportAndShare()` on tap. Reuse the `_ResetDataRow` visual pattern.

**5. Watch (Swift):** none.

## 7. Acceptance criteria

- [ ] A **"Export data"** row appears in Settings under a **DATA** section, styled consistently with existing rows.
- [ ] Tapping it produces the iOS share sheet with **two** attachments: a `.csv` and a `.json`, both named `ls-gym-track-export-<timestamp>.*`.
- [ ] The CSV contains **one row per logged set** across **every completed session**, with the exact columns in §8, header included.
- [ ] Weight appears in **both** the user's display unit (with a `unit` column) **and** in `kg`; toggling kg↔lb in Settings changes `weight_display`/`unit` but **never** `weight_kg`.
- [ ] The JSON matches the §8 shape: top-level `units`/`generated_at`/`app_version` metadata + `sessions[]` each with nested `sets[]`.
- [ ] Timestamps are **ISO-8601 UTC** in both files.
- [ ] Drop-set / grouped sets are represented (each member is its own row/object with `set_group` + `group_seq`); singletons have a null `set_group`.
- [ ] Export is **free** — no paywall, no gate, no count cap.
- [ ] On a **fresh install (no history)** the action still succeeds: header-only CSV + `"sessions": []` JSON.
- [ ] The Settings list **does not jank** during export; the row shows a busy indicator and disables re-tap while running; errors surface inline without crashing.
- [ ] No content in either file contains PII beyond workout data (no device IDs, file paths, account data).
- [ ] DB version is **unchanged (v6)**; no migration added.

## 8. Testing

**CSV schema (exact column order):**

```
date,session_id,program,day,exercise,set_number,reps,weight_display,unit,weight_kg,rir,set_group,group_seq
```

| Column | Source | Notes |
|---|---|---|
| `date` | `workout_sets.logged_at` | ISO-8601 UTC |
| `session_id` | `workout_sessions.id` | groups rows |
| `program` | `programs.name` | empty if program deleted/orphaned |
| `day` | `program_days.name` | empty if no day attached |
| `exercise` | `exercises.name` | |
| `set_number` | `workout_sets.set_index` | 1-based as stored |
| `reps` | `workout_sets.reps` | |
| `weight_display` | `WeightConv.fromKg(weight, unit)` | rounded per `weight.dart` rules |
| `unit` | settings | `kg` or `lb` |
| `weight_kg` | `workout_sets.weight` | raw storage value |
| `rir` | `workout_sets.rir` | |
| `set_group` | `workout_sets.set_group` | empty for singletons |
| `group_seq` | `workout_sets.group_seq` | `0` for the top/plain set |

**JSON shape example:**

```json
{
  "format": "ls-gym-track-export",
  "version": 1,
  "generated_at": "2026-06-23T07:41:00.000Z",
  "app_version": "1.2.0+8",
  "units": { "display": "lb", "storage": "kg" },
  "sessions": [
    {
      "id": "b3c1…",
      "started_at": "2026-06-21T18:02:00.000Z",
      "ended_at": "2026-06-21T18:54:00.000Z",
      "program": "PPL",
      "day": "Push A",
      "sets": [
        {
          "logged_at": "2026-06-21T18:05:30.000Z",
          "exercise": "Bench Press",
          "set_number": 1,
          "reps": 8,
          "weight_display": 176,
          "weight_kg": 80.0,
          "rir": 2,
          "set_group": null,
          "group_seq": 0
        }
      ]
    }
  ]
}
```

**Unit tests** (new `test/export_serializer_test.dart`, headless — no sqflite needed for the serializer itself since it takes an `ExportBundle`):

- `toCsv` emits the exact header row from §8.
- One `ExportSet` → exactly one CSV data row with correctly ordered/typed fields.
- **CSV escaping:** an exercise name containing a comma (`"Cable Fly, low"`) and one containing a double-quote are quoted/escaped per RFC-4180.
- **Unit honesty:** same `ExportBundle` rendered with `unit: lb` vs `unit: kg` keeps `weight_kg` identical and only changes `weight_display`/`unit`.
- **Drop set:** two sets sharing a `set_group` with `group_seq` 0/1 produce two rows/objects preserving the group key + sequence.
- `toJsonMap` round-trips through `jsonEncode`/`jsonDecode` and matches the §8 keys; empty bundle yields `"sessions": []`.
- ISO-8601 UTC: `generated_at` and per-set `logged_at` end in `Z`.

**DAO test** (extend `test/dao_test.dart` pattern — in-memory `sqflite_ffi`, `_openInMemory()` at `dao_test.dart:8`): seed a program/day/exercise + a completed session with 2 sets (incl. a drop-set group), assert `exportAllSessions()` returns them ordered, with names joined and abandoned/active sessions excluded.

**Manual matrix:**
- Export with kg, then lb → open CSV in Numbers, confirm `weight_display`/`unit` flip and `weight_kg` constant.
- Export the JSON, paste into a validator → valid; `sessions[].sets[]` nesting intact.
- Empty-history export shares successfully.
- Large history (200+ sessions) → no UI jank, share sheet appears promptly.
- Cancel the share sheet → row returns to idle, no leftover busy state, temp files don't accumulate visibly.

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `share_plus` adds a dependency the user wanted to avoid | Med | It's flutter.dev-federated (closest to first-party), single-purpose, widely vetted; the native-bridge alternative is *more* maintained surface. Pin a major version; revisit only if it bloats. |
| iOS share sheet returns no clear "shared" signal, leaving the row stuck busy | Low | Use `share_plus`'s `ShareResult`/completion to clear state; also clear on any return from the await regardless of result. |
| CSV opened in Excel mangles a leading-`=`/`+` exercise name (formula injection) | Low | Prefix-guard fields starting with `= + - @` in `toCsv` (per CSV-injection hardening); covered by a unit test. |
| Large history serialized on the UI thread janks Settings | Low (one user's data is small) | Await off the build path; wrap string-building in `compute()` if profiling shows >1 frame. AC requires no jank. |
| Display-unit rounding loses precision in `weight_display` | Expected/by-design | `weight_kg` is always present and lossless; `weight_display` is the convenience column. Documented in the JSON `units` metadata. |
| Orphaned data (deleted program/day) yields blank `program`/`day` | Med | LEFT JOINs + empty strings (CSV) / `null` (JSON); never drop the set row. Covered by the DAO test. |
| Temp files linger in the temp dir | Low | `getTemporaryDirectory()` is OS-reclaimable; optionally best-effort delete after share completes. |

## 10. Definition of done

- **Shippable bar:** the Settings → DATA → Export data action shares a complete-history CSV + JSON via the iOS share sheet, free, unit-honest, async, with the §7 acceptance criteria green and the §8 serializer/DAO tests passing in CI.
- **Positioning claim unlocked:** "**Your data exports any time**" becomes a *testable* App Store / marketing claim (`01-strategy-and-positioning.md`, trust pillar) and closes the named gap in `00-competitive-analysis.md` ("Data export (CSV)" #2) — surpassing Strong by exporting the **entire** history, not one workout.
- **Roadmap update:** mark **Data export** done in [02-roadmap.md](../02-roadmap.md) (Phase 0 / Free) and note the follow-on **JSON import / restore** SOW that this JSON format is designed to enable.
