# SOW-02b — Workout-Summary Share (text + image card)

> **Status:** ⬜ Not started · **Phase:** 0 · **Tier:** Free
> **Owner:** berke · **Est. size:** M
> **Strategic rationale:** The **word-of-mouth / viral lever** the competitive analysis said LS lacks — outbound "share my session to a friend" (WhatsApp/Messages), NOT the in-app social *feed* that [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) declines as bloat. See [00-competitive-analysis.md](../00-competitive-analysis.md) ("no social viral loop … must win on word-of-mouth-of-craft"). Decided with owner 2026-06-23.

Follows the [SOW-00 template](SOW-00-template.md). Reuses the **native share bridge from [SOW-02](SOW-02-data-export.md)** (no new dependency). Respects the [README](../README.md) non-negotiables.

---

## 1. Goal & Constraints
- **Delivers:** a **Share** affordance on the post-workout summary (and a completed session in history) that shares that one session's results to friends as **(a) a clean text block** (pastes into any chat) **and (b) a branded image "card"** (PNG), handed to the iOS share sheet together via the SOW-02 bridge.
- **Why now:** it is the cheap, on-brand viral loop — every shared card is free word-of-mouth and an App Store nudge ("logged with LS Gym Track"). Distinct from a social feed (which stays declined).
- **Hard constraints:** **Free forever.** **No new dependency** (image render uses Flutter's built-in `RepaintBoundary`→`toImage`; share uses the SOW-02 native bridge). **No account, no backend, no in-app feed.** Must not slow the summary screen; render + share are async with a busy state. No PII beyond the workout.
- **Non-goals:** no in-app social feed / following / likes / comments (declined in strategy); no leaderboards; no auto-post; no video; no per-set image (one card per session); no watch entry point.

## 2. Competitive context
| App | Has it? | Gap |
|---|---|---|
| **Hevy** | Shares to its own social feed + can export an image | Locked into Hevy's feed; we share *outward* to the user's existing chats |
| **Strong / Setgraph** | Workout-summary image share | Solid; we match on the card and add the text block + "logged with LS" attribution loop |
| **Alpha / RP / Juggernaut** | Thin/none | They under-invest in shareability |

- **Match:** a good-looking session card to the share sheet.
- **Surpass:** card **+** a plain-text block (universal, pastes anywhere), brand attribution as a soft acquisition loop, and it stays free.

## 3. Locked decisions
| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Formats | **Both** a text block and a PNG image card, shared together. | Text is universal (WhatsApp/SMS); the card is eye-catching/viral. Owner chose both. |
| 2 | Image render | **`RepaintBoundary` → `RenderRepaintBoundary.toImage(pixelRatio: 3)` → PNG** via `dart:ui` + `dart:typed_data`. No dependency. | Flutter-native screenshot of an off-screen branded widget; zero deps. |
| 3 | Share transport | **Reuse the SOW-02 `shareService.shareFiles(paths, {text})`** native bridge. | One bridge for both features; no `share_plus`. |
| 4 | Entry points | A share icon on **`summary_screen.dart`** (post-workout) and on a completed session opened from **history**. | Where the user is looking at results. |
| 5 | Card content | Program·day name, date, duration, exercise count, total tonnage, PR count; then per-exercise top set with a PR marker; footer "logged with LS Gym Track" + accent. | The session's "highlight reel"; mirrors `summary_screen` data + `PrDetector`. |
| 6 | Text content | Same data as plain text (no glyph-art), so it survives any chat. | Universal paste. |
| 7 | Data source | Reuse the existing post-session aggregation (`summary_screen` / `stats_provider` / `PrDetector`); read-only. **No schema change.** | The summary is already computed; don't duplicate logic. |
| 8 | Units | Honor the kg/lb display setting via `WeightConv`. | Consistent with the app. |

## 4. Design & UX
- **Affordance:** a share glyph in the `summary_screen` top bar (and the history-detail screen). Tap → busy state → render card + build text → share sheet.
- **The card** (off-screen widget, ~1080×1350 logical at pixelRatio 3) in the LS design system (dark, accent, Antonio/JetBrains/IBM Plex):
```
┌──────────────────────────────┐
│ LS                      ⌚ 47:00│
│ PUSH DAY · 23 JUN            │
│                              │
│ 12,400 kg   6 LIFTS   2 PR   │   ← big mono stats
│ ───────────────────────────  │
│ BENCH PRESS     100×5   ↗PR  │
│ OHP              60×8        │
│ INCLINE DB       30×10       │
│ …                            │
│ ───────────────────────────  │
│ logged with LS Gym Track     │   ← soft attribution (accent)
└──────────────────────────────┘
```
- **Text block:**
```
LS · PUSH DAY — 23 Jun
47 min · 6 exercises · 12,400 kg · 2 PRs

Bench Press   100kg×5  (PR)
OHP           60kg×8
Incline DB    30kg×10
…
— logged with LS Gym Track
```
- Tokens: `LsType.displayM/monoNumeral/monoData/monoMeta`, `LsTheme` accent/surface. Busy + error states mirror SOW-02's export row.

## 5. Data & schema changes
**None.** Read-only over the completed session already shown on `summary_screen`. No settings, no Pigeon, no DB bump (v6). Reuses the SOW-02 native bridge (which gains a `text` param on `shareFiles`).

## 6. Implementation plan
1. **domain:** `lib/features/share/domain/workout_summary.dart` — a plain `WorkoutSummary { programDay, date, duration, exerciseCount, tonnageKg, prCount, lines: [TopSetLine{exercise, reps, weightKg, isPr}] }`, built from the session + sets (+ `PrDetector`). Headless/testable.
2. **application:** `summary_text.dart` — pure `String buildSummaryText(WorkoutSummary, WeightUnit)` (the load-bearing **unit-tested** piece). `summary_card_renderer.dart` — `Future<String> renderCardPng(GlobalKey boundaryKey)` capturing the off-screen card to a temp PNG (via `path_provider`).
3. **presentation:** `summary_card.dart` — the branded card widget (wrapped in `RepaintBoundary`, built off-screen in an `Overlay`/`Offstage`). A `_ShareSummaryButton` on `summary_screen.dart` (+ history detail) that builds the summary, renders the PNG, builds the text, and calls `shareService.shareFiles([pngPath], text: summaryText)`.
4. **bridge:** extend SOW-02's `shareService` / `ShareHandler.swift` so `shareFiles` accepts an optional `text` (added to the `UIActivityViewController` activity items alongside the file).
5. **Swift:** none beyond the shared `ShareHandler` `text` param.

## 7. Acceptance criteria
- [ ] A share affordance on the post-workout summary and on a completed history session.
- [ ] Tapping shares **both** a PNG card and a text block to the iOS share sheet.
- [ ] The card and text show: program·day, date, duration, exercise count, total tonnage, PR count, and per-exercise top sets with PR markers — in the user's unit.
- [ ] Card renders crisply (pixelRatio ≥ 3), uses design tokens, no overflow for a long session (scrolls/scales).
- [ ] Free; no account; no in-app feed introduced.
- [ ] Async with a busy state; no jank on the summary screen; errors surface inline, no crash, no half-share.
- [ ] No new pub dependency; DB stays v6.

## 8. Testing
- **Unit (`test/summary_text_test.dart`, headless):** `buildSummaryText` — exact text for a known summary; PR markers present; kg vs lb; empty/edge (0 PRs, 1 exercise); long names don't break the format.
- **Widget:** the `summary_card` builds without overflow for 1, 6, and 20-exercise sessions; optional golden for the card at one size.
- **Manual matrix:** share to WhatsApp/Notes → text pastes cleanly + image attaches; long session card scales; kg↔lb flips values; cancel leaves no busy state / temp-file buildup.

## 9. Risks & mitigations
| Risk | Likelihood | Mitigation |
|---|---|---|
| Off-screen `toImage` capture flaky / blank | Med | Render in a mounted `Offstage`/`Overlay` with a frame settle before capture; fall back to text-only share if render fails. |
| Long session overflows the card | Med | Cap visible lines (top N exercises) with "+k more", or scale-to-fit; test 20-exercise case. |
| Native bridge unverifiable here | Med | Shared with SOW-02; device-verify once. |
| Feature creep toward a social feed | Low | Explicit non-goal; this is outbound share only. |

## 10. Definition of done
- **Shippable bar:** share affordance live on summary + history; shares a branded card + text via the native bridge; free; async; no dep; DB v6; §8 text test green.
- **Positioning unlocked:** a real **word-of-mouth loop** ("logged with LS Gym Track" in friends' chats) — the acquisition lever the strategy flagged as missing, without the social-feed bloat.
- **Roadmap:** mark SOW-02b done in [02-roadmap.md](../02-roadmap.md).
