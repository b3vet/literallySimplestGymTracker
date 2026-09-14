# Summary Screen — Redesign Spec

> **Target file:** `lib/features/workout/presentation/summary_screen.dart`
> **Route:** `/workout/summary/:sessionId` (post-workout). The history twin
> (`session_detail_screen.dart`) is **out of scope** for this pass — see §11 D6.
> **Status:** design spec, ready to implement. Dart is omitted by design.
> **App version:** v1.3.0 · **Date:** 2026-09-14

---

## 1. The job this screen does

A lifter has just racked the last bar. They are sweaty, standing up, holding the
phone in one hand, and they will look at this screen for **20–40 seconds** before
putting the phone in their pocket. There is exactly one question stack in their
head, in this order:

| # | Question | Today's screen answers it… |
|---|---|---|
| 1 | Is it saved? Am I done? | Implicitly, badly (topbar just shows a program name) |
| 2 | **Did I beat anything all-time?** | A 12px gold badge buried inside exercise card N |
| 3 | **Did I beat last time on this day?** | A 13px tag per card — you must assemble it yourself |
| 4 | How big was this session? | Three same-size pills, no comparison |
| 5 | Did I hit the plan? | Not at all — targets are loaded but never shown |
| 6 | What exactly did I lift? | Yes — 24 cramped mono rows, always, wanted or not |
| 7 | Should I bump my program? | Yes, but N separate taps scattered down the page |
| 8 | How's my 8-session trend? | **Second thing on the screen.** Nobody asks this here. |

The redesign re-sorts the screen to exactly that priority order. That single
re-sort is 80% of the fix. The rest is type scale and spacing rhythm.

**Frequency:** 3–6× per week, forever. This is a *repeat* screen, not an
onboarding screen — optimise for "answer at a glance," not for explanation.
No tooltips, no help text, no coach marks.

---

## 2. What is being cut or demoted (read this first)

Adding without subtracting is how a screen gets cramped. Here is the ledger.

| Element today | Verdict | Why |
|---|---|---|
| `WORKOUT SUMMARY` eyebrow | **CUT** | Says nothing the user doesn't know — they just tapped Finish. Replaced by `SAVED · SUN · SEP 14`, which confirms persistence *and* dates the session. |
| Three stat pills (DURATION / SETS / VOLUME) | **CUT as a group** | Three boxes of identical visual weight = zero hierarchy. Nothing is distinct, so nothing is remembered. Volume is promoted to the hero numeral; duration + sets demote to a mono run-in line in the masthead. |
| Total reps | **CUT (never add)** | No decision hangs off it. Vanity metric. |
| Average RIR | **CUT (never add)** | A session mean across compounds *and* cable flies is not a number anyone can act on. |
| **8-session volume trend chart** | **CUT from this screen → move to Stats** | The biggest change. It is currently the 2nd element on the page, it has no axis, no numbers and no touch target (so it is decoration), and it answers a Sunday-planning question at a post-workout moment. The comparison that matters *now* is "vs the last time I did this day," which Block 1 and Block 3 deliver at far higher information density. See open decision **D1**. |
| Always-visible per-set log (24+ rows) | **DEMOTE → expand on demand** | This is the literal "cramped, unreadable, space poorly used" complaint. The lifter performed these sets 90 seconds ago; verification is a minority need at this moment. Collapsed by default, one-tap `ALL SETS` master toggle, per-card tap to expand. |
| Per-exercise `RAISE TARGET` buttons | **KEPT, demoted to the secondary path** | They stay (hard constraint) inside the *expanded* exercise card. The primary path becomes one batched `UPDATE YOUR PROGRAM` card near the top: 3 updates go from 3 scroll→tap→snackbar cycles to **1 tap**. |
| `LsType.monoMicro` (12px) | **BANNED on this screen** | Smallest mono is the top readability complaint. Floor on this screen is `monoMeta` (13). Meaning-carrying meta (deltas, PR kind) goes to **15**. |

**New information added (10 facts, all from data already loaded except one):**
session volume delta vs previous same-day session (kg + %), days since this day
was last trained, aggregate up/matched/down/new tally, PR numbers and PR *kind*
(was a 12px badge), per-exercise program target (plan vs actual), per-exercise
previous-session actuals, batched program updates with old→new values, session
pace (avg/set), start + end clock times, not-in-plan tagging.

---

## 3. Interaction cost: before → after

Job: *"Did I improve, and bump my program if so."*

**Today** — land → hero day name (no outcome) → 3 pills (no comparison) → scroll
past chart → scroll through N cards reading a 13px tag on each and **holding the
running tally in your head** → tap `RAISE TARGET` on each qualifier (N taps, N
snackbars, each snackbar covering the next card) → scroll back up → topbar check.
≈ **4 scrolls · N+1 taps · N-item memory load · 0 aggregate answers.**

**Redesigned** — land → hero number + delta answers Q3 with **no scroll** → PR
strip answers Q2 → the up/matched/down bar answers "how many lifts improved" in
one glance → `APPLY ALL · 3` (1 tap) → topbar check, or scroll to `DONE`.
≈ **0 scrolls to the answer · 2 taps · 0 memory load.**

**Where the complexity moved (Tesler's law — state it out loud):** into the
provider. The screen now computes the deltas, the up/matched/down tally and the
batch-update list once, instead of making the user compute them by reading N
cards. One new DAO method is required (§10.1). And the per-exercise applied
state moves out of widget `State` into a session-scoped provider — which is
*also* the fix for the applied-state bug being worked separately (§4.4).

---

## 4. Scale and spacing contract

Two numbers first, because they are the whole design.

**Type ratio ladder** (6 tiers, hero:smallest = **5.5×**):

| Tier | Token + override | px | Used for |
|---|---|---|---|
| T1 | `LsType.displayHome.copyWith(fontSize: 72, height: 0.92)` | 72 | Day-name hero (size ladder, Block 0) |
| T2 | `LsType.monoNumeral.copyWith(fontSize: 64, fontWeight: w700)` | 64 | Total-volume numeral |
| T3 | `LsType.displayM.copyWith(fontSize: 30 / 26)` | 30 / 26 | Single-PR name / exercise-row name |
| T4 | `LsType.monoData.copyWith(fontSize: 20)` | 20 | Top set, set rows, target values |
| T5 | `LsType.monoMeta.copyWith(fontSize: 15)` | 15 | **Meaning-carrying** meta: deltas, PR kind, share link |
| T6 | `LsType.monoMeta` | 13 | Labelling meta: eyebrows, `4 SETS`, footer strip |

`LsType.monoMicro` (12) is used **nowhere** on this screen. `LsType.displayS`
(23) is used only for row titles inside the program-updates card.

**Spacing rhythm** (4 tiers, nothing else):

| Tier | Token | px | Rule |
|---|---|---|---|
| Block break | `LsGap.loose` | 22 | Between the numbered blocks in §5 |
| Within block | `LsGap.section` | 16 | Eyebrow → content, hairline → content |
| Within group | `LsGap.sub` / `LsGap.item` | 12 / 10 | Label ↔ value / between list rows |
| Tightest | `LsGap.tight` | 8 | Numeral ↔ its delta line, bar ↔ legend |

Card padding: `LsPad.cardStd` (18/18) for exercise rows — identical to the home
`_TileRow`, which is the calibration reference. `LsPad.cardSpacious` (20/20) for
the PR strip and the program-updates card only.

**Alignment:** the masthead (eyebrow + hero + meta) is **right-aligned**,
matching `home_screen` and `session_detail_screen`. Everything from Block 1 down
is **left-aligned**. This right→left flip is the same editorial move the home
screen already makes (right-aligned hero → left-aligned tiles).

---

## 5. Screen structure, top to bottom

```
┌──────────────────────────────────────────────────────┐
│ [ ]                          PPL      [ ↗ ]  [ ✓ ]   │  0  LsTopbar
├──────────────────────────────────────────────────────┤
│                           ── SAVED · SUN · SEP 14    │  0  masthead
│                                                      │
│                                       PUSH A         │     T1 72
│                          47 MIN · 6 LIFTS · 22 SETS  │     T6 13
│                                                      │
│  ── TOTAL VOLUME                                     │  1  the number
│                                                      │
│  12,480 KG                                           │     T2 64 + unit 18
│  ▲ +1,240 KG · +11%  VS LAST PUSH A                  │     T5 15 accent
│  ══════════════════════════════════════════════════  │     2px accent rule
│                                                      │
│ ┌──────────────────────────────────────────────────┐ │  2  PR strip
│ │▌  ★ NEW PERSONAL RECORD                          │ │     (conditional)
│ │▌                                                 │ │
│ │▌  BENCH PRESS                                    │ │     T3 30
│ │▌  102.5 KG × 5  ·  HEAVIEST EVER                 │ │     T4 20 + T5 15
│ └──────────────────────────────────────────────────┘ │
│                                                      │
│  ── VS LAST PUSH A · 7 DAYS AGO                      │  3  progression
│                                                      │     (conditional)
│  ████████████████████████░░░░░░▓▓▓▓▓▓░░░░            │     10px bar
│  4 UP  ·  1 MATCHED  ·  1 DOWN                       │     T6 13
│                                                      │
│  ── UPDATE YOUR PROGRAM                              │  4  batched action
│ ┌──────────────────────────────────────────────────┐ │     (conditional)
│ │  BENCH PRESS                                     │ │
│ │  TARGET  100 → 102.5 KG                    [ ↑ ] │ │
│ │  ──────────────────────────────────────────────  │ │
│ │  SEATED ROW                                      │ │
│ │  TARGET  75 → 80 KG                        [ ↑ ] │ │
│ │  ──────────────────────────────────────────────  │ │
│ │  CABLE FLY                          NOT IN PLAN  │ │
│ │  3 × 12 @ 22.5 KG                          [ + ] │ │
│ │                                                  │ │
│ │  ┌────────────────────────────────────────────┐  │ │
│ │  │            APPLY ALL  ·  3                 │  │ │
│ │  └────────────────────────────────────────────┘  │ │
│ └──────────────────────────────────────────────────┘ │
│                                                      │
│  ── THE LIFTS · 6                        ALL SETS ⌄  │  5  the log
│ ┌──────────────────────────────────────────────────┐ │
│ │ ┌──┐                                             │ │
│ │ │01│  BENCH PRESS                         [ PR ] │ │
│ │ └──┘  102.5 KG × 5 · 4 SETS         ▲ +2.5 KG    │ │
│ └──────────────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────────────┐ │
│ │ ┌──┐                                             │ │
│ │ │02│  INCLINE DB PRESS                           │ │
│ │ └──┘  34 KG × 10 · 3 SETS              — MATCHED │ │
│ └──────────────────────────────────────────────────┘ │
│                          … 4 more                    │
│                                                      │
│  ──────────────────────────────────────────────────  │  6  footer
│  19:20 → 20:07  ·  2:08 AVG / SET                    │     T6 13
│                                                      │
│  ┌──────────────────────────────────────────────────┐│
│  │  ↗   SHARE THIS WORKOUT                          ││     ghost
│  └──────────────────────────────────────────────────┘│
│  ┌──────────────────────────────────────────────────┐│
│  │                   DONE                           ││     primary, 64
│  └──────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────┘
```

Scroll container: a single `ListView` inside `LsScreen(topGap: LsGap.loose)`.
**No pinned footer** — the topbar check is the always-available exit; the bottom
`DONE` is the scroll terminus (peak-end rule: the last thing seen should be a
resolution, not a truncated list).

---

### Block 0 — Masthead

**Topbar** (`LsTopbar`, unchanged structurally, `showBack: false`):
- `title`: program name, uppercased; fallback `'COMPLETE'` when `programName == null`.
- `trailing`: `ShareSummaryButton` + 10px + `LsIconSquare(Icons.check, semanticLabel: 'Done', onTap: → context.go('/'))`. **Both kept.**

**Eyebrow** — `Align(centerRight, EyebrowLabel('SAVED · SUN · SEP 14'))`
(`DateFormat('EEE · MMM d')`). Label `t.surface.text2`, stripe `t.accent.accent`.
This is the Nielsen-#1 status confirmation *and* the date, in one line.

→ `LsGap.sub` (12)

**Hero** — day name, uppercased, `textAlign: right`, colour `t.surface.text`.
Style `LsType.displayHome.copyWith(fontSize: S, height: 0.92)`, `maxLines: 2`,
`overflow: ellipsis`. **Size ladder** (deterministic, no `FittedBox`):

```
len(dayName) ≤ 12       → S = 72     "PUSH A", "LEG DAY"
len(dayName) 13..22     → S = 56     "UPPER BODY A"
len(dayName) > 22       → S = 44     "FULL BODY STRENGTH B"
```
Then, if `MediaQuery.of(context).textScaler.scale(1) > 1.15`, step S down one
rung. Fallback when `dayName == null` → `'WORKOUT'`.

→ `LsGap.sub` (12)

**Meta line** — `LsType.monoMeta` (T6 13), `t.surface.text2`, right-aligned,
`maxLines: 1`:

`47 MIN · 6 LIFTS · 22 SETS`

Duration: `{m}M` under an hour, `{h}H {m}M` over. `LIFTS` = distinct exercise
count. `SETS` = **logical** set count (`groupedSetsFor` groups, so a drop set
counts once — matches how the active screen counts). Singular forms `1 LIFT`,
`1 SET`. Kept to 3 chunks deliberately: at 13px mono with 1.82 tracking, ~37
characters is the width budget at 361pt of content, and a 4th chunk overflows
once the duration reaches `1H 12M`.

→ `LsGap.loose` (22)

---

### Block 1 — The number

`EyebrowLabel('TOTAL VOLUME')`, left-aligned.

→ `LsGap.sub` (12)

**Numeral row** — baseline-aligned `Row`:
- Value: `summaryTonnageGrouped(WeightConv.fromKg(totalKg, unit))` — reuse the
  existing helper in `features/share/application/summary_text.dart` (thousands
  separated). Style T2 (`monoNumeral` @ **64**, `w700`), `t.surface.text`,
  tabular figures (already on `_mono`). Wrapped in
  `FittedBox(fit: scaleDown, alignment: centerLeft)` bounded to the content width
  so a 7-figure lb tonnage cannot overflow.
- 8px gap, then the unit: `KG` / `LB` in
  `LsType.monoMeta.copyWith(fontSize: 18)`, `t.surface.text2`, baseline-aligned
  with the numeral.

→ `LsGap.tight` (8)

**Delta line** — T5 (`monoMeta` @ **15**), `maxLines: 1`, an icon + two coloured
runs:

| Condition | Icon | Text | Colour |
|---|---|---|---|
| `delta > 0` | `Icons.arrow_upward` 14 | `+1,240 KG · +11%` then ` VS LAST PUSH A` | value `t.accent.accent`, tail `t.surface.text2` |
| `delta < 0` | `Icons.arrow_downward` 14 | `−980 KG · −8%` then ` VS LAST PUSH A` | value `LsSignals.danger`, tail `t.surface.text2` |
| `delta == 0` | `Icons.remove` 14 | `MATCHED LAST PUSH A` | `t.surface.text2` |
| First-ever session (§7.5) | `Icons.flag` 14 | `FIRST SESSION LOGGED · BASELINE SET` | `t.accent.accent` |
| No prev session for this day | — | `FIRST TIME ON PUSH A` | `t.surface.text2` |
| No program day at all | — | **line omitted**; the accent rule moves up by `LsGap.sub` | — |

Percent = `delta / prevTotal`, rounded to a whole percent, omitted when
`prevTotal == 0`. Never show a percent without the absolute value beside it.

→ `LsGap.section` (16)

**Accent rule** — `Container(height: 2, color: t.accent.accent)`, full content
width. The masthead terminator; the only accent rule on the page.

→ `LsGap.loose` (22)

---

### Block 2 — PR strip · *conditional*

**Shown when** `prCount > 0` **AND** this is not the user's first-ever session
(§7.5 — on session #1 every lift is technically a weight PR, and "6 PERSONAL
RECORDS" on day one devalues the badge forever after).

Container: `LsCard(padding: LsPad.cardSpacious)` with the decoration overridden:
- background `LsTheme.of(context).prDimBg` (**new token — §10.2**)
- border `Border.all(color: LsSignals.pr)` at 1px
- a **left bar**: `Container(width: 4)` filled `LsSignals.pr`, flush to the
  card's left edge inside the `r3` clip (`ClipRRect` + `Row`).

> **Light-mode colour rule — non-negotiable.** `LsSignals.pr` (#FFB400) on a
> light surface is **1.78:1**. Gold ink is dark-mode only. On a light theme the
> PR strip's **text is `t.surface.text`** (near-black, ~14:1 on the gold tint);
> gold is used only for the left bar, the border, and the star glyph. On dark,
> gold text on `t.surface.surface` is 10.1:1 and is used throughout.
> *(The existing `_PrBadge` — monoMicro 12 gold on a 20%-alpha gold fill — fails
> light-mode contrast today. This replaces it.)*
>
> Note: when the user's accent **is** yellow, `LsSignals.pr` and the accent
> coincide. Distinctiveness is preserved by shape language, not hue — the PR
> strip is a filled card with a 4px bar; the accent rule above it is a 2px line.

**Variant A — one PR (common case):**
```
▌  ★  NEW PERSONAL RECORD            ← Icons.star 16 + T5 15
▌
▌  BENCH PRESS                       ← T3 30, t.surface.text
▌  102.5 KG × 5  ·  HEAVIEST EVER    ← T4 20 (text) + T5 15 (PR ink)
```
Internal gaps: eyebrow → name `LsGap.section` (16); name → values `LsGap.tight` (8).

**Variant B — two or more PRs:**
```
▌  ★  3 PERSONAL RECORDS
▌
▌  BENCH PRESS                       ← T3 26
▌  102.5 KG × 5 · HEAVIEST EVER      ← T4 18 + T5 13
▌                                    ← LsGap.section (16) between PR rows
▌  SEATED ROW
▌  80 KG × 12 · MOST REPS AT 80 KG
```

PR-kind copy — never `↑W` / `↑R`:
- `PrKind.weight` → `HEAVIEST EVER`
- `PrKind.reps` → `MOST REPS AT {weight}` (e.g. `MOST REPS AT 80 KG`)

**Motion (celebration 2 of 2):** the 4px left bar wipes from height 0 → full over
**320ms** with `LsMotion.slowCurve`, starting 120ms after first build. Text is at
full opacity from frame 1 — the animation never delays reading. Gated on
`reduceMotionOf(context)` (reuse the helper in
`features/onboarding/presentation/onboarding_fx.dart`; consider promoting it to
`core/util/`). Runs **once**, on the post-workout route only.

→ `LsGap.loose` (22)

---

### Block 3 — Vs last time · *conditional*

**Shown when** `prevByExercise != null` (a previous completed session exists for
this program day).

`EyebrowLabel('VS LAST {DAY} · {n} DAYS AGO')`. Day count =
`session.startedAt.difference(prevSession.startedAt).inDays`, floored;
`1 DAY AGO` singular; `TODAY` when 0. **No new query** — the provider already
fetches the previous session, it just needs to keep `prevSession.startedAt` on
`_SummaryData`.

→ `LsGap.section` (16)

**Proportion bar** — one horizontal `Row` of flex-weighted segments,
`height: 10`, `borderRadius: LsRadius.r1`, `2px` gaps between segments. Only
non-zero segments render; a single non-zero segment fills the full width.

| Segment | Meaning | Colour |
|---|---|---|
| UP | beat last time | `t.accent.accent` |
| MATCHED | identical top set | `t.surface.borderStrong` |
| DOWN | below last time | `LsSignals.danger` |
| NEW | no previous data for this exercise | `t.surface.surface3` |

**Classification rule — must be byte-identical to the per-exercise rule in
Block 5**, so the aggregate and the rows can never disagree: compare the
exercise's top weight this session vs last; if equal, compare max reps at that
top weight. Greater → UP, equal → MATCHED, less → DOWN, no previous sets → NEW.

→ `LsGap.tight` (8)

**Legend** — one line, T6 13, `·`-separated, only non-zero terms:
`4 UP · 1 MATCHED · 1 DOWN · 1 NEW`. The **numeral** takes the segment colour;
the **word** is `t.surface.text2`. The bar itself is `ExcludeSemantics` — this
line is its text alternative.

→ `LsGap.loose` (22)

---

### Block 4 — Update your program · *conditional*

**Shown when** `session.programDayId != null` **AND** at least one exercise
qualifies. Qualification is exactly today's rule, unchanged:
- in the plan **and** (`topWeight > pe.defaultWeightKg` **or** weight-PR) → **RAISE**
- not in the plan → **ADD**
- otherwise → not listed

`EyebrowLabel('UPDATE YOUR PROGRAM')` → `LsGap.section` (16) →
`LsCard(padding: LsPad.cardSpacious)`.

**Row anatomy** (each row ≥ 64pt tall; the whole row is the tap target):

```
┌───────────────────────────────────────────────────────┐
│  BENCH PRESS                                          │  LsType.displayS @23
│  TARGET   100 → 102.5 KG                        [ ↑ ] │  T6 13 + T4 20 + 44sq
└───────────────────────────────────────────────────────┘
```
- Name: `LsType.displayS.copyWith(fontSize: 23)`, `t.surface.text`,
  `maxLines: 1`, ellipsis. For an ADD row a right-aligned `NOT IN PLAN` tag in
  T6 13 `t.surface.text3` sits on the same line.
- Value line, RAISE: `TARGET` label T6 13 `t.surface.text2`; then `100` in
  `t.surface.text3`, ` → ` in `t.surface.text3`, `102.5 KG` in `t.surface.text`
  — all T4 20. The old value dimmed and the new value at full contrast *is* the
  direction indicator.
- Value line, ADD: `3 × 12 @ 22.5 KG` (sets × max reps @ top weight), T4 20,
  `t.surface.text`.
- Rows separated by `LsHairline` with `LsGap.section` (16) above and below.

#### 4.1 Applied vs not-applied — the unmistakable state

This is the hard constraint. Today the two states differ only by hairline colour
(accent border + accent text → border + `text3` text) — two low-contrast outline
states, easy to miss and impossible to scan across a list. Replace with a
**fill-vs-outline** binary, which is already the app's established language for
"selected" (`LsChoiceChip`). **Three redundant, colour-independent signals:**

| | NOT APPLIED | APPLIED |
|---|---|---|
| **Trailing square** (44×44, `LsRadius.r2`) | `Colors.transparent` fill, `1px t.accent.accent` border, glyph `Icons.arrow_upward` (raise) / `Icons.add` (add) @18 in `t.accent.accent` | **`t.accent.accent` fill**, no border, glyph **`Icons.check`** @20 in `t.accent.accentInk` |
| **Row background** | `Colors.transparent` | `LsTheme.of(context).accentDimBg` (opaque tint in light mode — the token already handles it) |
| **Status word** (right of the name, T6 13) | *(none)* | `UPDATED` (raise) / `ADDED` (add), `t.accent.accent` |
| **Value line** | `100 → 102.5 KG` | `102.5 KG` only — the arrow disappears because there is nothing left to change |
| **Tap** | applies | **inert** (`onTap: null`, no ripple) |

Fill + tint + word means the state survives greyscale, colour-blindness and a
half-second glance. A user scanning the card sees filled squares vs outlined
squares with zero reading.

#### 4.2 Batch control

Bottom of the card, after `LsGap.section` (16), full-width `LsButton`
(`minHeight: LsBox.button` 54):

| Applied count | Label | Variant |
|---|---|---|
| 0 of N | `APPLY ALL · N` | `primary` |
| 1..N−1 of N | `APPLY REMAINING · K` | `primary` |
| N of N | `UNDO ALL` | `secondary` |

Single-qualifier case (N == 1): **no batch button at all** — the row's own
trailing square is sufficient; a full-width button for one row is noise.

**Apply behaviour** (unchanged semantics, unchanged DAO calls): applies
immediately, no confirm dialog — undo beats confirm. One snackbar, 5s, with
`UNDO`. A batch apply shows `3 PROGRAM TARGETS UPDATED` with a single `UNDO`
that reverses all three. `ref.invalidate(dayExercisesProvider(dayId))` after
every mutation, as today.

#### 4.3 Copy

| Situation | String |
|---|---|
| Section eyebrow | `UPDATE YOUR PROGRAM` |
| Raise, not applied | `TARGET  100 → 102.5 KG` |
| Raise, applied | `TARGET  102.5 KG` + `UPDATED` |
| Add, not applied | `3 × 12 @ 22.5 KG` + `NOT IN PLAN` |
| Add, applied | `3 × 12 @ 22.5 KG` + `ADDED` |
| Snackbars | `3 PROGRAM TARGETS UPDATED` / `BENCH PRESS TARGET → 102.5 KG` / `CABLE FLY ADDED TO PUSH A` |

#### 4.4 State ownership — required for the applied-state bug

The applied flag **must not** live in `_ProgramTargetButtonState`. Spec:

```
programUpdatesProvider(sessionId)
  → Map<exerciseId, ProgramUpdate {
        kind: raise | add,
        currentTargetKg, proposedTargetKg,
        targetSets, targetRepsMin, targetRepsMax,   // for add
        applied: bool,
        undo: Future<void> Function()?,
    }>
```
Both Block 4's rows **and** the per-exercise button inside an expanded Block 5
card read and write this one provider. Applying in either place updates the
other live, and the state survives any rebuild, scroll recycle, theme flip,
unit flip or `AnimatedSize` pass. This is the design's answer to "applied state
gets lost" — the visual treatment in §4.1 is only trustworthy if the state is.

→ `LsGap.loose` (22)

---

### Block 5 — The lifts

**Section header row:**
```
  ── THE LIFTS · 6                            ALL SETS ⌄
```
- Left: `EyebrowLabel('THE LIFTS · {n}')`.
- Right: expand-all toggle. `LsType.monoMeta` @13 in `t.surface.text2`, plus
  `Icons.expand_more` @18 rotating 180° when expanded. Label flips
  `ALL SETS` ↔ `HIDE SETS`. Wrapped in `SizedBox(height: 44)` + `InkWell` so the
  tap target is 44pt tall even though the text is 13px.
- Toggling sets every card's expanded flag; individual cards can then still be
  toggled independently. The state is **not persisted** across sessions — every
  new summary opens collapsed.

→ `LsGap.section` (16), then cards separated by `LsGap.item` (10).

#### 5.1 Collapsed row — the default

```
┌────────────────────────────────────────────────────┐
│ ┌────┐                                             │
│ │ 01 │   BENCH PRESS                        [ PR ] │
│ └────┘   102.5 KG × 5  ·  4 SETS       ▲ +2.5 KG   │
└────────────────────────────────────────────────────┘
```
- `LsCard(padding: LsPad.cardStd, onTap: toggleExpanded)` — identical geometry to
  the home `_TileRow`, deliberately, so the summary reads as the same app.
- **Index square:** `LsBox.tileIndex` (44×44), `t.accent.accentDim` fill,
  `LsRadius.r2`, label `01`/`02` zero-padded in
  `LsType.monoMeta.copyWith(fontSize: 14, fontWeight: w700)`, `t.accent.accent`.
  Verbatim reuse of the home tile index.
- `LsGap.inline` (12) gap.
- **Name:** T3 (`displayM` @ **26**), `t.surface.text`, `maxLines: 2`, ellipsis,
  in an `Expanded`. One step above the home tile's 23 because this is content,
  not navigation — a deliberate, documented deviation.
- **Value line** (6px under the name): `102.5 KG × 5` in T4 20 `t.surface.text`
  — the single most-read datum on the row, so it is the largest mono — then
  ` · 4 SETS` in T6 13 `t.surface.text2`.
- **Delta** (right-aligned, on the value line): icon @14 + T5 15.
  `▲ +2.5 KG` accent / `▼ −5 KG` danger / `— MATCHED` `t.surface.text2` /
  `NEW` `t.surface.text3`. Reps-only delta: `▲ +2 REPS`.
- **PR chip** (right-aligned, on the name line), only when that exercise set a
  PR: text `PR` in `LsType.monoMeta.copyWith(fontSize: 13, fontWeight: w700)`,
  ink `Color(0xFF0A0B0C)` (= `lsDark.bg`), fill `LsSignals.pr`, padding 8h/4v,
  `LsRadius.r2`. Dark ink on gold = 10:1 in **both** themes — this is why the
  chip is filled rather than tinted. It also matches the share card's badge.
- **`NOT IN PLAN` tag** (takes the PR-chip slot when there is no PR and
  `planByExercise[id] == null`): T6 13, `t.surface.text3`.

Row height ≈ 44 + 36 = **80pt**. The whole card is the tap target.

#### 5.2 Expanded state

Tapping the card (or the master toggle) reveals, inside the same card:

```
┌────────────────────────────────────────────────────┐
│ ┌────┐                                             │
│ │ 01 │   BENCH PRESS                        [ PR ] │
│ └────┘   102.5 KG × 5  ·  4 SETS       ▲ +2.5 KG   │
│                                                    │
│  ────────────────────────────────────────────────  │  LsHairline
│                                                    │
│  TARGET  4 × 8-10 @ 100 KG                         │  T6 13, text2
│                                                    │
│   1    102.5 KG × 5                        RIR 2   │  T4 20 / T6 13
│   2    102.5 KG × 5                        RIR 1   │
│   3     95 KG × 8                                  │
│   4     95 KG × 6  ↓ 80 KG × 4  ↓ 65 KG × 3        │  drop set inline
│                                                    │
│  LAST TIME   100 KG × 5  ·  4 SETS                 │  T6 13, text3
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │  ↑  RAISE TARGET → 102.5 KG                  │  │  per-exercise action
│  └──────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

- Hairline: `LsHairline`, full card width, `LsGap.section` (16) above and below.
- **`TARGET` line** *(new — this data is loaded today and never shown)*:
  `TARGET  {targetSets} × {repsMin}-{repsMax} @ {defaultWeight}`, T6 13,
  `t.surface.text2`. Omitted when `planByExercise[id] == null`. If
  `repsMin == repsMax`, render a single number. Then `LsGap.sub` (12).
- **Set rows**, one per `groupedSetsFor` group, `LsGap.item` (10) apart:
  - Ordinal column: `SizedBox(width: 24)`, `1`..`N`, T6 13, `t.surface.text3`.
    *(Replaces today's 64pt `SET 1` label — reclaims **40pt of row width**,
    which is precisely the "space poorly used" complaint.)*
  - Value: `{weight} × {reps}` in T4 **20** (up from 18), `t.surface.text`.
  - Drop sets render **inline on one row**: ` ↓ 80 KG × 4 ↓ 65 KG × 3` appended
    in T4 18 `t.surface.text2`; overflow wraps to a second line within the same
    row block. *(Replaces today's stacked sub-rows.)*
  - `RIR n`: right-aligned column, T6 13, `t.surface.text2`, only when `rir > 0`.
    Its own column so it stops interrupting the weight × reps number.
- **`LAST TIME` line** *(new)*: `LAST TIME   100 KG × 5  ·  4 SETS` — the
  previous session's top set and set count for this exercise. T6 13,
  `t.surface.text3`, `LsGap.section` (16) above. Makes the delta verifiable
  instead of asking for trust. Omitted when there is no previous data.
- **Per-exercise program action** *(kept — hard constraint)*: the same widget as
  a Block 4 row's control, rendered here as a labelled button
  (`RAISE TARGET → 102.5 KG` / `SET TARGET → …` / `ADD TO PUSH A`), reading the
  same `programUpdatesProvider` entry. Applied state uses **the same
  fill-vs-outline treatment as §4.1**: not applied = transparent fill + accent
  border + accent label; applied = **accent fill + `accentInk` label + check
  glyph**, label `TARGET SET` / `ADDED`, tap inert. `LsGap.section` (16) above,
  `minHeight: 44`.
- **Motion:** `AnimatedSize`, `LsMotion.base` (200ms), `Curves.easeOut`; the
  chevron rotates 180° over the same duration. Under reduce-motion: instant, no
  `AnimatedSize`.

→ after the last card, `LsGap.loose` (22)

---

### Block 6 — Footer

```
  ──────────────────────────────────────────────────   LsHairline
  19:20 → 20:07  ·  2:08 AVG / SET                     T6 13, text3, centred

  [ ↗  SHARE THIS WORKOUT ]                            LsButton ghost, expand
  [          DONE          ]                           LsButton primary, 64
```
- `LsHairline` → `LsGap.section` (16) → meta strip.
- **Meta strip:** `HH:mm → HH:mm  ·  m:ss AVG / SET`, T6 13, `t.surface.text3`,
  centred. Pace = `duration ÷ logicalSetCount`, formatted `m:ss`. Omitted when
  the set count is 0. *(This is the one place a "density" stat earns its keep:
  cheap, real, and out of the way.)*
- → `LsGap.loose` (22) → **SHARE** — `LsButton(label: 'SHARE THIS WORKOUT',
  icon: Icons.ios_share, variant: ghost, expand: true)`, wired to the same
  `ShareSummaryButton` action. *Rationale for a second entry point: the topbar
  glyph is a 44pt icon most users never notice, and the moment of highest share
  intent is immediately after reading your PRs, not before. SOW-02b's whole
  strategic case is the word-of-mouth loop — give it a real target.*
- → `LsGap.item` (10) → **DONE** — `LsButton(label: 'DONE', variant: primary,
  expand: true, minHeight: LsBox.cta)` → `context.go('/')`. Accent-filled; the
  only primary below Block 4, and the last thing seen.
- → `LsGap.screenBot` (10) + safe area.

---

## 6. Motion budget

Exactly **two** one-shot animations, both gated on `reduceMotionOf(context)` and
both running only on the post-workout route (never when components are reused
for a history session):

| # | What | Duration | Curve | Note |
|---|---|---|---|---|
| 1 | Hero tonnage counts 0 → value | **450ms** | `Curves.easeOutCubic` | Tabular figures prevent width jitter. The number is legible the whole time — this does not gate reading, it makes the number feel earned. |
| 2 | PR strip left bar wipes 0 → full height | **320ms**, 120ms delay | `LsMotion.slowCurve` | Draws the eye to the highest-value element as the screen settles. Text is opaque from frame 1. |

Under reduce-motion both render their final state immediately. Everything else
(expand/collapse) uses `LsMotion.base` 200ms and is a response to a tap, not
ambience.

**Explicitly rejected:** confetti, scale-in card cascades, staggered list
entrances, shimmer skeletons, odometer number flips. Achievement here comes from
72px type and a 5.5× ratio, not from particles.

---

## 7. States

### 7.1 Loading
Do **not** render a bare `CircularProgressIndicator` on an unthemed `Scaffold`
(today's behaviour flashes the wrong background and makes the screen jump into
existence). Instead:
- Render `LsScreen` + `LsTopbar` immediately (title `COMPLETE`, done button live
  and functional — the user can always leave).
- Data is local SQLite and typically resolves in <100ms, so **suppress the
  skeleton for the first 120ms**. If data lands inside 120ms, go straight to
  content with no intermediate frame.
- After 120ms show a **static** skeleton (no shimmer): bars of
  `t.surface.surface2`, `LsRadius.r2`, at the real final heights — eyebrow
  13 × 140w and hero 72 × 220w and meta 13 × 200w (all right-aligned), then a
  64 × 240w numeral bar, then three 80pt-tall `LsRadius.r3` card blocks.

### 7.2 Error
`LsScreen` + topbar, left-aligned block:
```
── SOMETHING WENT WRONG
COULDN'T LOAD THIS SESSION            T3 26
Your sets are saved. Try again, or    bodyM, text2
open it from History.
[ TRY AGAIN ]   secondary → ref.invalidate(_sessionSummaryProvider(id))
[ GO HOME ]     ghost     → context.go('/')
```
The reassurance line is the load-bearing copy — the user's fear is that the
workout was lost. Never surface the raw exception string in the UI.

### 7.3 Session not found (`d == null`)
Same shell. `THIS SESSION ISN'T HERE` / "It may have been deleted." /
`[ GO HOME ]` primary.

### 7.4 Completed session with zero sets
Masthead renders normally (so the user isn't dumped onto a broken page), then a
single card replaces Blocks 1–5:
```
── NO SETS LOGGED
NOTHING RECORDED                      T3 26
You finished before logging a set.    bodyM, text2
Nothing was added to your history.
[ BACK TO HOME ]  primary
```
Footer is suppressed (nothing to share). **See open decision D3** — this may be
a product bug rather than a state worth designing for.

### 7.5 First-ever workout
Detection: `completedSessionCount() == 1` (new DAO method, §10.1).
- Block 1 delta line → `FIRST SESSION LOGGED · BASELINE SET` in `t.accent.accent`.
- Block 2 **suppressed** — on session #1 `PrDetector` returns `PrKind.weight`
  for every exercise (there is no history to beat), so "6 PERSONAL RECORDS" is
  hollow and permanently devalues the badge. Per-exercise `PR` chips in Block 5
  are suppressed for the same reason.
- Block 3 replaced by a **baseline card** (`LsCard`, `LsPad.cardSpacious`):
  ```
  ── BASELINE
  THIS IS YOUR BENCHMARK               T3 30
  Every future PUSH A gets measured    bodyM, text2
  against today.
  ```
  This converts the weakest empty state on the screen into the achievement it
  actually is.
- Block 4 renders normally (adding substituted lifts to the plan is *more*
  useful on day one, not less).

### 7.6 First time on *this day* (but not first ever)
Block 1 delta line → `FIRST TIME ON PUSH A`, `t.surface.text2`. Block 3 hidden.
Block 2 renders normally — PRs are all-time, not day-scoped, so they are valid.
Per-exercise deltas show `NEW` in `t.surface.text3`.

### 7.7 No program day (`programDayId == null`, orphaned day)
- Topbar title → `COMPLETE`; hero → `WORKOUT`.
- Block 1 delta line **omitted**; the accent rule moves up by `LsGap.sub`.
- Block 3 hidden. Block 4 hidden entirely. `TARGET` lines in Block 5 omitted.
- Everything else renders. Nothing should read as an error — an ad-hoc session
  is a legitimate session.

### 7.8 Edge sizes
| Case | Behaviour |
|---|---|
| 1 exercise, 1 set | Everything renders; Block 3 bar is a single full-width segment; the legend shows one term; the Block 4 batch button is suppressed (N == 1). |
| 15+ exercises | The page just gets long — correct for a scroll page. No pagination, no "show more". `ALL SETS` on 15 lifts makes a very long page; that is opt-in and acceptable. |
| Longest strings | Day name → 3-step size ladder (Block 0). Exercise name → `maxLines: 2` + ellipsis in an `Expanded`; PR chip is fixed width. Tonnage → `FittedBox(scaleDown)`. Masthead meta → `maxLines: 1` + ellipsis. |
| lb unit | All values through `WeightConv.format`; tonnage through `summaryTonnageGrouped`. A 7-figure lb tonnage is the scaleDown case above. |
| Light theme | Every rule in Block 2 applies. Verify `accentDimBg` (not `accentDim`) is used for applied rows. |
| Offline / permissions | N/A — local SQLite only; no network, no OS permissions on this screen. |

---

## 8. Accessibility requirements

- **Merged semantics nodes** (otherwise VoiceOver reads "12,480", "KG", "▲" as
  three meaningless fragments):
  - Masthead → `"Push A, saved Sunday September 14. 47 minutes, 6 lifts, 22 sets."`
  - Block 1 → `"Total volume 12,480 kilograms. Up 1,240 kilograms, 11 percent, versus last Push A."`
  - Block 2 → `"New personal record. Bench press, 102.5 kilograms for 5 reps. Heaviest ever."`
  - Block 3 bar → `ExcludeSemantics`; the legend line carries it.
  - Each collapsed lift row → `"Bench press. Personal record. 102.5 kilograms for 5 reps, 4 sets. Up 2.5 kilograms."` + hint `"Double tap to show sets."`
  - Applied program row → the applied state **must** be in the semantics label
    (`"Bench press target updated to 102.5 kilograms."`), not conveyed by fill alone.
- **Tap targets:** exercise card ≈80pt · program row ≥64pt · trailing square
  **44×44** · `ALL SETS` toggle wrapped to 44pt height · topbar squares 44.
- **Contrast:** all text ≥4.5:1; T1–T3 display type ≥3:1 as large text. The
  light-mode gold rule (Block 2) is the one that breaks if ignored.
- **Colour independence:** every accent/danger signal is paired with a glyph
  (▲ ▼ — ✓) *and* a word (UP / DOWN / MATCHED / UPDATED). The screen is fully
  readable in greyscale.
- **Dynamic Type:** the hero ladder steps down one rung above 1.15× scale; all
  other tiers wrap or ellipsize rather than clip. No fixed-height text boxes.
- **Motion:** §6; both animations gated on `MediaQuery.disableAnimations`.

---

## 9. Copy sheet

| Key | String |
|---|---|
| Topbar title | `{PROGRAM NAME}` · fallback `COMPLETE` |
| Masthead eyebrow | `SAVED · SUN · SEP 14` |
| Hero fallback | `WORKOUT` |
| Masthead meta | `47 MIN · 6 LIFTS · 22 SETS` |
| Block 1 eyebrow | `TOTAL VOLUME` |
| Delta, up | `+1,240 KG · +11%` + ` VS LAST PUSH A` |
| Delta, down | `−980 KG · −8%` + ` VS LAST PUSH A` |
| Delta, equal | `MATCHED LAST PUSH A` |
| Delta, first ever | `FIRST SESSION LOGGED · BASELINE SET` |
| Delta, first on day | `FIRST TIME ON PUSH A` |
| PR eyebrow, 1 | `NEW PERSONAL RECORD` |
| PR eyebrow, n | `3 PERSONAL RECORDS` |
| PR kind, weight | `HEAVIEST EVER` |
| PR kind, reps | `MOST REPS AT 80 KG` |
| Block 3 eyebrow | `VS LAST PUSH A · 7 DAYS AGO` |
| Block 3 legend | `4 UP · 1 MATCHED · 1 DOWN · 1 NEW` |
| Block 4 eyebrow | `UPDATE YOUR PROGRAM` |
| Block 4 batch | `APPLY ALL · 3` / `APPLY REMAINING · 1` / `UNDO ALL` |
| Block 5 eyebrow | `THE LIFTS · 6` |
| Block 5 toggle | `ALL SETS` / `HIDE SETS` |
| Expanded target | `TARGET  4 × 8-10 @ 100 KG` |
| Expanded prev | `LAST TIME   100 KG × 5  ·  4 SETS` |
| Footer meta | `19:20 → 20:07  ·  2:08 AVG / SET` |
| Footer share | `SHARE THIS WORKOUT` |
| Footer done | `DONE` |
| Baseline card | `BASELINE` / `THIS IS YOUR BENCHMARK` / "Every future PUSH A gets measured against today." |
| Empty session | `NO SETS LOGGED` / `NOTHING RECORDED` / "You finished before logging a set. Nothing was added to your history." |
| Error | `SOMETHING WENT WRONG` / `COULDN'T LOAD THIS SESSION` / "Your sets are saved. Try again, or open it from History." |
| Not found | `THIS SESSION ISN'T HERE` / "It may have been deleted." |

All display/mono strings are uppercased at the call site (existing convention).
Body copy stays sentence case (IBM Plex). No exclamation marks anywhere — the
type does the celebrating.

---

## 10. What the implementer needs added

### 10.1 One new DAO method (please add)
```
Future<int> completedSessionCount();   // SELECT COUNT(*) WHERE status = 'completed'
```
Needed only for the first-ever / baseline state (§7.5).
`listCompletedSessions(limit: 2).length` is an acceptable stand-in if you'd
rather not touch the DAO.

### 10.2 Two token additions
```
LsSignals.prDimDark  = pr.withValues(alpha: 0.12)
LsSignals.prDimLight = Color(0xFFFFF1CC)     // opaque gold tint for light mode
LsTheme.prDimBg      => isLight ? prDimLight : prDimDark
```
This mirrors the existing `accentDimSolidLight` / `LsTheme.accentDimBg` pattern
verbatim — same problem (alpha tints wash out on white), same solution shape.

### 10.3 Provider changes — no new queries beyond 10.1
- `_SummaryData` keeps `prevSession.startedAt` (already fetched, currently thrown
  away) → "7 DAYS AGO" for free.
- `_SummaryData` keeps `prevTotalVolumeKg` (sum over `prevSets`, already fetched)
  → the Block 1 delta and percent for free.
- Derive in the provider, not the widget: `logicalSetCount`, `perExerciseVolume`,
  the `up/matched/down/new` tally, `topSetPerExercise`, `prevTopSetPerExercise`,
  `qualifyingProgramUpdates`.
- Add `programUpdatesProvider(sessionId)` per §4.4 — session-scoped, owns the
  applied flags and undo closures.
- **Delete** `_tonnageTrendProvider` and `_TrendCard` from this file (see D1).

### 10.4 Not needed for v1 — deliberately
Weekly/monthly session count, streaks, all-time 1RM estimates, weekly tonnage,
lifetime session totals. These are all *planning* information; the lifter asks
them on a rest day, not with chalk still on their hands. They belong on the
Stats screen. Keeping them off this screen is what makes the hierarchy work.

---

## 11. Open decisions (yours, not mine)

| # | Decision | My recommendation |
|---|---|---|
| **D1** | Delete the 8-session volume-trend chart from this screen, or keep it? | **Delete it**; let Stats own trends. If you want it kept, put it *below* Block 5 and above the footer, and give it real numbers (min/max labels + the current point's value) so it stops being decoration. It should never be the second thing on the page again. |
| **D2** | Exercise cards collapsed by default? | **Yes, collapsed**, with the `ALL SETS` master toggle. This is the single largest contributor to "cramped / unreadable". A fallback would be expanded-by-default for sessions with ≤3 exercises — but I'd avoid a conditional default; consistency beats cleverness here. |
| **D3** | Should finishing a session with **zero sets** even produce a summary? | Looks like a product bug, not a UI state. I'd have `completeSession` treat a zero-set session as abandoned and route home with a snackbar. §7.4 designs the state in case you keep it. |
| **D4** | Should "hit the top of the rep range at target weight" also qualify for `RAISE TARGET`? | Out of scope for this pass — it changes progression semantics, not layout. Worth a separate look; it's arguably the more common progression trigger than beating the target weight. |
| **D5** | Second `SHARE` entry point in the footer, in addition to the topbar? | **Yes.** Highest share intent is *after* reading your PRs. Costs one ghost button. |
| **D6** | Should `session_detail_screen.dart` (history) adopt this layout? | Not in this pass. It's a genuinely different job (archival review, editable sets) and it should stay editable. Share the *components* (PR chip, exercise row, vs-last bar), not the page. |

---

## 12. Out of scope for v1, and why

- **History detail screen** — different job (D6).
- **Tabs / sub-pages / a "details" route** — excluded by the brief, and
  unnecessary: expand-in-place gives a glance level and a focused level on one
  surface without a second navigation level.
- **Editing sets from the summary** — that's history's job; editing here would
  invalidate the PR and delta maths you just showed.
- **Charts of any kind** — the vs-last bar is a proportion, not a chart. No axes,
  no time series, on this screen.
- **Streaks, weekly totals, 1RM estimates** — §10.4.
- **Localisation** — this repo ships literal English strings; the copy sheet in
  §9 is written to be extractable later if that changes.

---

## 13. Acceptance checklist

- [ ] Block order is exactly 0→6; the trend chart is gone from this file.
- [ ] Zero `LsType.monoMicro` usages on this screen; no font size below 13.
- [ ] Every spacing value is an `LsGap.*` / `LsPad.*` token — no bare `SizedBox(height: 14)`.
- [ ] Every colour is `t.surface.*` / `t.accent.*` / `LsSignals.*` — no literals except the documented `lsDark.bg` PR-chip ink.
- [ ] Applied vs not-applied differs by **fill, background tint, and a word** — verifiable in a greyscale screenshot.
- [ ] Applied state survives: scroll away and back, expand/collapse, theme flip, unit flip, app backgrounding.
- [ ] Light theme: no gold text anywhere; PR strip text is `t.surface.text`.
- [ ] Dark theme: PR strip text is `LsSignals.pr`.
- [ ] All eight states in §7 render without overflow at 360pt and at iPhone Pro Max width.
- [ ] Reduce-motion on: no count-up, no bar wipe, no `AnimatedSize`.
- [ ] VoiceOver reads the masthead, hero stat, PR strip and each lift row as single coherent sentences.
- [ ] `flutter analyze` clean; no overflow warnings in widget tests for 1-, 6- and 20-exercise sessions.

---

## 14. Decisions taken at implementation (2026-09-14, v1.4.0)

Berke was away, so the §11 open decisions were resolved as follows. Each is
reversible; flag any you disagree with and it's a small change.

| # | Decision | Taken | Note |
|---|---|---|---|
| D1 | Trend chart | **Deleted from this screen** | `stats_screen.dart` already renders a tonnage `LineChart`, so no information is lost from the app — only from the wrong moment. `_tonnageTrendProvider` and `_TrendCard` are gone from `summary_screen.dart`; `WorkoutDao.totalTonnageBySession` stays (Stats uses it). |
| D2 | Collapsed by default | **Yes**, with the `ALL SETS` master toggle | Expansion state is held in `_SummaryBodyState`, above the `ListView` — same reason the applied flag moved to a provider. |
| D3 | Zero-set session | **Kept as a UI state** (§7.4) | Changing what `completeSession` does is a behaviour change outside this brief. Worth raising separately. |
| D4 | "Top of rep range" as a RAISE trigger | **Not done** | Progression semantics, not layout. Qualification is byte-identical to v1.3.0. |
| D5 | Footer share | **Yes** | `ShareSummaryButton` gained a `ShareButtonStyle.wide` variant, so both entry points run the exact same action. |
| D6 | History detail adopting this layout | **Not in this pass** | `session_detail_screen.dart` is untouched. |

### Deviations from the spec

- **PR strip on a first-ever session** is suppressed by suppressing PRs at the
  source: `sessionSummaryProvider` drops the `PrDetector` map entirely when
  `completedSessionCount() <= 1`, so `prCount`, the PR strip and the per-lift
  `PR` chips all go quiet together and can't disagree.
- **Count-up + bar wipe** use `TweenAnimationBuilder`, not `AnimationController`.
  The 120ms PR-bar hold is expressed as an `Interval(120/440, 1)` over a 440ms
  tween rather than a delayed start, which is the same curve with no timer.
- **Block 4's trailing hairline** was dropped: `LsGap.loose` plus the next
  block's eyebrow already separates it, and the extra rule read as clutter.
