# SOW-06 — Monetization Foundation (entitlement · lifetime + annual · paywall)

> **Status:** ⬜ Not started · **Phase:** 2 · **Tier:** Infra
> **Owner:** berke · **Est. size:** L
> **Strategic rationale:** Builds the entitlement + purchase + paywall plumbing the paid moat (SOW-07 RIR auto-progression, SOW-09 HRV, SOW-10 analytics) gates against — and encodes the trust pillar (honest pricing, no retroactive paywall, lifetime honored forever) directly in code. See the Monetization model table in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) and the "we have *zero* infrastructure" gap in [00-competitive-analysis.md](../00-competitive-analysis.md).

This SOW follows [SOW-00-template.md](SOW-00-template.md). It is grounded in the real Riverpod tri-layer and the SharedPreferences settings pattern (`lib/core/settings/settings_repository.dart`), the design system (`lib/core/theme/app_theme.dart`), and the non-negotiables in [../README.md](../README.md). **Zero monetization exists in the repo today** — no `in_app_purchase`, no `purchases_flutter`, no StoreKit bridge, no `isPro` flag anywhere (`pubspec.yaml` confirms).

---

## 1. Goal & Constraints

**What this delivers (user-visible):**
- A single source-of-truth **entitlement** (`isPro`) the app can read synchronously anywhere, derived from the user's real App Store purchases, cached offline, restorable on any device signed into the same Apple ID.
- A **purchase flow** for two products only: **$29.99 lifetime** (non-consumable) and **~$19.99/year annual** (auto-renewable). Restore Purchases. No monthly.
- An honest **paywall screen** in the design system, reachable from a locked feature or from Settings, with copy that states the trust promise in plain language ("one-time purchase, honored forever; no feature you have today is ever removed").

**Why now:** Phase 2 races the Alpha clock. SOW-07 (the paid RIR differentiator) has nothing to gate until this lands, so this is sequenced **before** SOW-07 per [02-roadmap.md](../02-roadmap.md). It also closes the explicit "Monetization — we have *zero* infrastructure" gap in [00-competitive-analysis.md](../00-competitive-analysis.md) §"Where we're behind".

**Hard constraints (non-negotiable — from [../README.md](../README.md)):**
- **Free core forever.** Core logging, RIR *field* entry, data export (SOW-02), basic charts/stats, plate calculator (SOW-01), warm-up calc (SOW-04), rest timer, and **all watch logging** are NEVER gated. Gating any of them is a retroactive paywall and is forbidden.
- **No monthly** at launch. Disqualifying for a tracker per the Reddit-revealed preference in the strategy doc.
- **Lifetime is never revoked.** Once granted, `isPro` from a lifetime purchase is honored forever, even if a future build adds a subscription tier. (StrongLifts revoked its lifetime in Jan 2026 → "bait and switch". That is the exact mistake to never make.)
- **Honest, non-dark-pattern paywall.** No fake countdowns, no pre-ticked trials, no obscured price, no hard-to-find restore, no nag-on-launch. Contrast with GymStreak (33.5/100 legitimacy) and Juggernaut billing traps from [00-competitive-analysis.md](../00-competitive-analysis.md).
- **Minimal / first-party deps.** Prefer the first-party Flutter `in_app_purchase` plugin over a third-party SaaS (RevenueCat). See Decision #1.

**Non-goals:**
- No actual paid feature ships here — this is pure infrastructure. SOW-07/09/10 consume the `requiresPro` gate this SOW exposes.
- No server-side receipt validation backend (we have no server; validation is on-device StoreKit transaction verification — see Decision #3 and Risk R4).
- No promo codes, intro offers, family sharing config, or win-back offers at launch (App Store Connect can add later without code changes).
- No Android / Google Play billing (iOS-only product; out of scope per the deferred list).
- No paywall A/B testing harness.

## 2. Competitive context

Every credible rival monetizes; we are the only one with **no** infrastructure. The strategic edge is not *that* we charge but *how*:

| Rival | Model | The trap we avoid |
|---|---|---|
| **Strong** | $99.99 lifetime, basics Pro-gated | Paywalls basic logging — we never gate core |
| **Hevy** | $74.99 lifetime, generous free | Closest to our stance; we match free-core generosity, add wrist-RIR as the paid hook |
| **StrongLifts** | $59.99/yr — **revoked its lifetime (Jan 2026)** | The "bait and switch" — our lifetime is contractually honored forever in code |
| **GymStreak / Juggernaut** | $59.99/yr, billing "scam" (33.5/100) | Dark-pattern billing — our paywall is honest by design |
| **Alpha Progression** | $59.99/yr | We price **deliberately below** it ($19.99/yr + $29.99 lifetime) to win the trust-wary indie filter |

**Match** = a working, restorable, sandbox-tested purchase + entitlement system with two clean SKUs. **Surpass** = the paywall *itself* becomes a trust artifact — the honesty of the copy ("no feature ever removed", visible restore, no monthly) is a positioning claim no incumbent can make, because they all spent that trust.

## 3. Locked decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | **Purchase layer technology** | **First-party Flutter `in_app_purchase` plugin** (pub.dev, maintained by flutter.dev), wrapping StoreKit. **NOT** RevenueCat, **NOT** a hand-rolled Pigeon/StoreKit 2 bridge. | Matches the "minimal/first-party deps" preference. `in_app_purchase` is the official plugin, no third-party SaaS account, no per-MTR fee, no vendor lock-in, no extra SDK weight. A hand-rolled StoreKit 2 Pigeon bridge is *more* native control but is net-new Swift + a Pigeon contract to maintain (we already maintain one for the watch — adding a second is avoidable complexity for a 2-SKU catalog). RevenueCat is rejected: it adds a network dependency and a third party in the trust path, contradicting the "honest by design / no betrayal surface" pillar. (Caveat: `in_app_purchase` exposes only StoreKit 1 semantics on its stable channel; that is sufficient for a non-consumable + a single auto-renewable — see Risk R4 for the validation consequence.) |
| 2 | **Price points & SKUs** | **`pro_lifetime` = $29.99 (non-consumable)** + **`pro_annual` = ~$19.99/year (auto-renewable)**. **No monthly.** | Locked verbatim from the Monetization table in [01-strategy-and-positioning.md](../01-strategy-and-positioning.md). Deliberately below Alpha/Boostcamp $59.99/yr to win the trust-wary indie filter; accept lower ARPU for trust + conversion. |
| 3 | **Entitlement source of truth** | A single **`isPro` bool**, derived at runtime from StoreKit's restored/active transactions, **cached in SharedPreferences** (`settings.entitlement.is_pro` + `settings.entitlement.source` + `settings.entitlement.checked_at`). On-device verification only; no server. | Mirrors the existing settings cache pattern (`settings_repository.dart`). The cache enables a synchronous, offline-correct read everywhere; StoreKit is the authority and reconciles the cache on launch + on purchase/restore. |
| 4 | **Lifetime durability rule** | A lifetime grant, once cached, is **never auto-revoked** by the app. `source == lifetime` short-circuits all gating to "unlocked" permanently. Annual entitlement *can* lapse (it's a subscription) but lapse only re-locks *additive* features, never core. | Encodes the "honored forever / no betrayal surface" promise in code. Even if economics later force a subscription-only tier, the lifetime flag and free core both survive. |
| 5 | **The free/paid seam** | Exhaustive table below. Everything shipped or specced through Phase 1 is **free**; only the three Phase 2-3 *additive* engines are paid. | The "basic/smart seam — never gate core logging" from the strategy table. The seam is defined here so SOW-07/09/10 inherit it rather than re-litigating it. |
| 6 | **Offline grace** | Cached `isPro` is trusted **indefinitely while offline**; never lock a paid feature because StoreKit is unreachable. Reconcile only when a fresh authoritative result arrives. | A user on a gym floor with no signal must never lose a feature they paid for. Fail *open* for paid features; fail *closed* only on a confirmed authoritative "not entitled". |
| 7 | **Paywall trigger policy** | Paywall is shown **only** on explicit intent: tapping a locked feature's unlock affordance, or a "Go Pro" row in Settings. **Never** on app launch, never interstitial, never timed. | The honest-paywall constraint. No nag-on-launch dark pattern. |

### The free / paid seam (locked — the controlling table)

| Capability | Tier | Notes |
|---|---|---|
| Core set logging (reps / weight / **RIR field**) | **FREE forever** | The acquisition gate. Gating = predicted death. |
| Program creation / editing / day structure | **FREE** | |
| Rest timer + Live Activity | **FREE** | |
| Mid-workout swap / skip / session inserts / drop sets / supersets (SOW-08) | **FREE** | |
| Basic progress charts & stats (Epley 1RM, volume, top-set trends) | **FREE** | Already shipped; explicitly confirmed free here (roadmap SOW-06 note). |
| **Data export (CSV/JSON)** (SOW-02) | **FREE forever** | A trust signal; gating it is a recommendation-stopper. |
| Plate calculator (SOW-01) | **FREE** | |
| Warm-up set calculator (SOW-04) | **FREE** | |
| **All Apple Watch logging** | **FREE** | The crown wedge is core, never gated. |
| — — — — — — — — — — | — | — |
| **RIR auto-progression nudge** (SOW-07) | **PAID** | The headline differentiator. |
| **HRV readiness modifier** (SOW-09) | **PAID** | |
| **Advanced analytics & trends** (SOW-10) | **PAID** | Additive upgrade for data nerds. |

**Invariant:** the FREE block above is closed and append-only. A feature may move FREE→FREE or be added as PAID, but **no FREE row ever becomes PAID**. A PR that flips a free row to paid is a retroactive paywall and must be rejected in review.

## 4. Design & UX

### Screens / sheets touched
- **New:** `PaywallScreen` (full-screen route `/paywall`) — the purchase surface.
- **New:** `ProLockBadge` / `ProGate` widgets — the affordance shown where a paid feature would be, that routes to `/paywall`.
- **Modified:** `lib/features/settings/presentation/settings_screen.dart` — add a `MEMBERSHIP` section: a "Go Pro" row when free, a "Pro — lifetime/annual" status row + "Restore Purchases" when entitled. Mirrors the existing `_Section` + `Material/InkWell` row pattern already in that file.

### Design-system mapping
- Built from `LsScreen` + `LsTopbar` (`lib/core/widgets/layout.dart`); price cards reuse the `Material` + `Container` + `Border.all(t.surface.border)` + `LsRadius.r3` pattern seen in `settings_screen.dart`.
- Headline in `LsType.displayL` (uppercased), price in `LsType.monoNumeral`, benefit rows in `LsType.bodyM` with `EyebrowLabel` section heads (`lib/core/widgets/brand.dart`).
- Primary CTA = `LsButton` (accent-filled via `t.accent.accent` / `accentInk`); secondary "Restore Purchases" + "Maybe later" as `TextButton`. The selected plan card uses the `t.accentDimBg` + `Border.all(t.accent.accent)` treatment already used by the rest-timer picker band in `settings_screen.dart`.
- Accent-aware and light/dark-aware automatically via `LsTheme.of(context)` — no hardcoded colors.

### ASCII mock — Paywall

```
┌─────────────────────────────────────┐
│  ‹ Back                       LS PRO │   ← LsTopbar, displayL title
│                                      │
│  UNLOCK THE SMART LAYER              │   ← LsType.displayL, uppercased
│                                      │
│  Effort-aware progression, on your   │   ← bodyM, text2
│  wrist. Everything you log today     │
│  stays free, forever.                │
│                                      │
│  ┌───────────────┐ ┌───────────────┐ │
│  │  LIFETIME  ✓  │ │   ANNUAL      │ │   ← two LsChoiceChip-style cards
│  │   $29.99      │ │  $19.99 / yr  │ │     selected = accentDimBg + accent border
│  │  one-time     │ │  renews yearly│ │
│  │  pay once     │ │               │ │
│  └───────────────┘ └───────────────┘ │
│                                      │
│  WHAT PRO ADDS                       │   ← EyebrowLabel
│  • RIR auto-progression nudges       │   ← bodyM rows, accent check glyph
│  • HRV readiness (when shipped)      │
│  • Advanced analytics & trends       │
│                                      │
│  ALWAYS FREE                         │   ← EyebrowLabel — the honesty block
│  • All logging, RIR, export          │
│  • Charts, plate calc, watch         │
│  • No feature you have is removed    │
│                                      │
│  ┌──────────────────────────────────┐│
│  │       CONTINUE — $29.99          ││   ← LsButton, accent, expand:true
│  └──────────────────────────────────┘│
│        Restore Purchases             │   ← TextButton, always visible
│                                      │
│  One-time purchase, honored forever. │   ← bodyS, text3 — the promise line
│  No subscription required. Cancel a  │
│  yearly plan anytime in Settings.    │
└─────────────────────────────────────┘
```

### Copy (locked tone — honest, no dark patterns)
- Headline: **"UNLOCK THE SMART LAYER"**
- Sub: **"Effort-aware progression on your wrist. Everything you log today stays free, forever."**
- The "ALWAYS FREE" block is mandatory and lists what is never gated — this is the trust artifact.
- Footer promise line (mandatory): **"One-time purchase, honored forever. No feature you have today is ever removed."**
- Restore Purchases is **always visible**, never buried in a menu.
- No countdown, no "X people bought this", no pre-selected trial, no "limited time".

### Watch behavior
- **No watch UI for purchase or paywall.** The watch reads entitlement from the phone snapshot only. If a paid watch feature (a future SOW-07 on-wrist nudge) is locked, the watch silently shows the free behavior — it never renders a paywall on a 45mm screen. Entitlement is added to the existing watch snapshot (`lib/features/workout/application/watch_snapshot.dart`) as a single `isPro` bool so the watch can branch without round-tripping. (No new Pigeon method required if it rides the existing snapshot; if a dedicated push is preferred, extend `pigeons/watch_bridge.dart` — left to SOW-07.)

## 5. Data & schema changes

**No SQLite schema change.** Entitlement is not workout data; it lives in SharedPreferences like every other app setting, so `_dbVersion` in `lib/core/db/database.dart` and `lib/core/db/migrations.dart` are **untouched**.

**Settings/flags to add** (the `settings_repository.dart` pattern — new keys, new `AppSettings` fields, new read/write methods, new `SettingsNotifier` setters):

```
settings.entitlement.is_pro      bool    cached entitlement (default false)
settings.entitlement.source      string  'none' | 'lifetime' | 'annual'
settings.entitlement.checked_at  int     epoch ms of last authoritative StoreKit reconcile
```

These mirror exactly how `_kOnboardingComplete` / `_kLiveActivity` are declared, read with a default, and written through a `write…()` method in `SettingsRepository`, then surfaced as immutable fields on `AppSettings` with a `copyWith` and a `SettingsNotifier.set…()`.

**Watch bridge:** add `isPro` to the watch snapshot payload (`watch_snapshot.dart` / `watch_bridge.g.dart`) — a single bool, additive. No breaking Pigeon contract change for this SOW.

## 6. Implementation plan

Ordered by layer; names are real files to add (➕) or modify (✏️).

**1. Dependency**
- ✏️ `pubspec.yaml` — add `in_app_purchase: ^3.x` under `dependencies`. Configure StoreKit capability in Xcode (In-App Purchase capability on the Runner target).

**2. domain/**
- ➕ `lib/features/monetization/domain/entitlement.dart` — `enum EntitlementSource { none, lifetime, annual }`, `class Entitlement { final bool isPro; final EntitlementSource source; final DateTime? checkedAt; }` (immutable + `copyWith`), and a `ProProduct` enum mapping to the two product IDs (`pro_lifetime`, `pro_annual`).

**3. data/ (settings persistence)**
- ✏️ `lib/core/settings/settings_repository.dart` — add the three `_kEntitlement…` keys, read them in `read()` (with defaults), add `writeEntitlement(Entitlement)`; add `isPro` / `entitlementSource` / `entitlementCheckedAt` fields to `AppSettings` + `copyWith`.
- ✏️ `lib/core/settings/settings_provider.dart` — add `setEntitlement(Entitlement)` to `SettingsNotifier`.

**4. data/ (StoreKit gateway)**
- ➕ `lib/features/monetization/data/purchase_service.dart` — thin wrapper over `InAppPurchase.instance`: `queryProducts()`, `buy(ProProduct)`, `restorePurchases()`, and a `Stream<List<PurchaseDetails>> purchaseStream`. Translates StoreKit purchase/restore results into an `Entitlement` (any active `pro_lifetime` → `lifetime`; else any active `pro_annual` → `annual`; else `none`). Verifies `PurchaseDetails.status` and completes pending transactions (`completePurchase`). Isolated so it can be faked in tests.

**5. application/ (the entitlement provider — single source of truth)**
- ➕ `lib/features/monetization/application/entitlement_controller.dart` —
  - `entitlementProvider` (a `Notifier<Entitlement>`) seeded synchronously from the cached settings (`ref.read(settingsProvider).isPro/...`) so reads are instant and offline-correct.
  - On construction + on app resume, kicks an async `reconcile()` that listens to `PurchaseService.purchaseStream` / runs `restorePurchases()` and writes the authoritative result back through `SettingsNotifier.setEntitlement` (which re-emits state).
  - **Durability:** `reconcile()` never downgrades a cached `lifetime` to `none`; it only upgrades, or downgrades `annual`→`none` on a confirmed lapse. Honors offline grace (Decision #6) by ignoring transient/network errors.
  - Exposes a convenience `isProProvider = Provider<bool>((ref) => ref.watch(entitlementProvider).isPro)`.
- ➕ `lib/features/monetization/application/pro_gate.dart` — `bool requiresPro(WidgetRef ref)` helper + a `ProGate` wrapper widget that, given a feature, either renders the child (entitled) or a `ProLockBadge` that routes to `/paywall`. SOW-07/09/10 call this — they do not read settings directly.

**6. presentation/**
- ➕ `lib/features/monetization/presentation/paywall_screen.dart` — the screen in §4, driven by `purchaseServiceProvider.queryProducts()` for live localized prices (never hardcode price strings — read StoreKit's localized `price`), `entitlementProvider` for state, `LsButton` CTA wired to `buy(...)`, visible `restorePurchases()`.
- ➕ `lib/features/monetization/presentation/pro_lock_badge.dart` — the small "PRO" affordance.
- ✏️ `lib/core/router/app_router.dart` — add `GoRoute(path: '/paywall', …)`. (Entitlement does **not** gate any route via redirect — paywall is opt-in only, per Decision #7.)
- ✏️ `lib/features/settings/presentation/settings_screen.dart` — add the `MEMBERSHIP` `_Section`: "Go Pro" row → `/paywall` when free; status + "Restore Purchases" when entitled.

**7. watch (Swift) — minimal**
- ✏️ `lib/features/workout/application/watch_snapshot.dart` (+ regenerated `watch_bridge.g.dart`) — include `isPro` in the snapshot so the watch can branch. No new paywall on the watch. (Deeper watch consumption is SOW-07's concern.)

## 7. Acceptance criteria

- [ ] `in_app_purchase` is the only IAP dependency added; no `purchases_flutter` / RevenueCat / hand-rolled StoreKit Pigeon bridge appears in the diff.
- [ ] Exactly two products exist (`pro_lifetime` $29.99 non-consumable, `pro_annual` ~$19.99 auto-renewable). **No monthly product** is defined anywhere.
- [ ] `entitlementProvider` returns a correct `isPro` synchronously on cold launch from the SharedPreferences cache, with **no** network call required to read it.
- [ ] Buying lifetime in the StoreKit sandbox flips `isPro` → true with `source == lifetime` and persists across app restart.
- [ ] Buying annual in sandbox flips `isPro` → true with `source == annual`.
- [ ] **Restore Purchases** on a fresh install (same sandbox Apple ID) restores entitlement without re-charging.
- [ ] A cached `lifetime` entitlement is **never** revoked by the app — verified by a unit test that feeds `reconcile()` a transient/empty StoreKit result and asserts `isPro` stays true.
- [ ] Offline (StoreKit unreachable): a previously-entitled user keeps all paid features (fail-open); a never-entitled user is not falsely upgraded.
- [ ] Every row in the FREE seam table is reachable and fully functional with `isPro == false` (core logging, RIR field, export, basic charts, plate calc, warm-up, rest timer, watch logging) — confirmed by a checklist run.
- [ ] Paywall is shown **only** on explicit user intent; it never appears on launch or as a timed interstitial.
- [ ] Paywall displays StoreKit's **localized** price (not a hardcoded string), shows a visible Restore button, shows the "ALWAYS FREE" block and the "honored forever / no feature removed" promise line, and contains no countdown/scarcity/pre-ticked-trial dark pattern.
- [ ] Settings shows a correct MEMBERSHIP section reflecting current entitlement.
- [ ] The watch snapshot carries `isPro`; the watch shows free behavior when locked and renders no paywall.

## 8. Testing

**Unit tests** (Dart, no device — fake the `PurchaseService` behind an interface; SharedPreferences via `SharedPreferences.setMockInitialValues`):
- ➕ `test/entitlement_controller_test.dart` —
  - cold read from cache returns correct `isPro` / `source` synchronously;
  - lifetime purchase result → `isPro` true, `source == lifetime`, persisted;
  - annual purchase → `source == annual`;
  - `reconcile()` with empty/transient result **does not** revoke a cached lifetime (durability);
  - confirmed annual lapse → `source == none`, `isPro` false, **but** core-feature gating helpers still return "allowed";
  - offline error path leaves cached entitlement untouched (fail-open).
- ➕ `test/pro_gate_test.dart` — `requiresPro` / `ProGate` returns child when entitled, lock affordance when not; FREE-seam features never call the gate.
- These mirror the existing settings/persistence test style; they do **not** touch `sqflite_ffi` since there's no DB change (contrast `test/dao_test.dart` / `test/queries_test.dart`, which do).

**Widget test:**
- ➕ `test/paywall_screen_test.dart` — renders both plan cards, shows a (faked) localized price, Restore button present, "ALWAYS FREE" block present, CTA disabled until a plan is selected, no launch-time auto-present.

**Manual matrix (StoreKit sandbox — required before ship):**
| Scenario | Expectation |
|---|---|
| Sandbox buy `pro_lifetime` | `isPro` true, source lifetime, survives restart |
| Sandbox buy `pro_annual` | `isPro` true, source annual |
| Restore on fresh install, same Apple ID | entitlement restored, no double charge |
| Decline / cancel purchase sheet | no entitlement change, no crash |
| Airplane mode, previously entitled | all paid features remain unlocked |
| Airplane mode, never entitled | no false upgrade; paywall still openable |
| Annual sandbox renewal expiry | re-locks paid only; core untouched |
| `.storekit` local config file run | products query returns 2 SKUs, correct prices |

Use an Xcode **StoreKit configuration file** (`Configuration.storekit`) for local/CI simulator testing without App Store Connect round-trips, plus a real **sandbox Apple ID** for the final pre-ship pass.

## 9. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **R1 — Lifetime under-monetizes loyal users; ~40% of lifetime-deal apps fail in 3yr** (the strategy doc's honest caveat) | Medium | Lifetime unlocks *additive* features only; core stays free; the seam invariant (§3) means a future subscription tier can be added **without** breaking the lifetime promise or gating core. Annual SKU exists precisely to capture recurring revenue alongside lifetime. |
| **R2 — Accidental retroactive paywall** (someone flips a FREE row to PAID) | Medium | The seam table is the controlling spec; the FREE block is append-only; PR review must reject any FREE→PAID flip. Acceptance criterion + the durability unit test encode it. |
| **R3 — Lifetime wrongly revoked** by a bad reconcile (the StrongLifts mistake, in code) | Low/High-impact | `reconcile()` is upgrade-only for `lifetime`; durability unit test asserts a transient empty StoreKit result never clears a cached lifetime; offline grace (Decision #6) fails open. |
| **R4 — On-device validation only / `in_app_purchase` is StoreKit-1-flavored** → jailbreak receipt spoofing possible | Low | Accepted: we have no server, the products are cheap, the threat actor (a lifter spoofing a $30 unlock) is negligible, and the cost of a validation backend contradicts the minimalism discipline. If fraud ever materializes, a StoreKit 2 Pigeon bridge (Decision #1's rejected alternative) becomes the upgrade path — no data migration needed since entitlement is a derived cache. |
| **R5 — App Store review rejection** (missing restore, unclear terms, undisclosed subscription) | Medium | Restore is always visible; the paywall states price, renewal terms, and "cancel anytime in Settings"; link Privacy Policy + Terms (EULA) per Apple guideline 3.1.2. Pre-submit checklist in §10. |
| **R6 — Sandbox flakiness masks real bugs** | Medium | Test against both a local `.storekit` config (deterministic) and a real sandbox Apple ID; never ship on green local-config alone. |
| **R7 — Price/SKU drift between code and App Store Connect** | Low | Never hardcode price strings — always render StoreKit's localized `price`; product IDs are the only constants and live in one `ProProduct` enum. |

## 10. Definition of done

**Shippable bar:**
- `in_app_purchase` integrated; two products (`pro_lifetime` $29.99, `pro_annual` ~$19.99/yr) defined in **App Store Connect** and in a local `Configuration.storekit`; no monthly SKU.
- `entitlementProvider` is the single source of truth; cached in SharedPreferences; synchronous + offline-correct; lifetime durable; restore working — all verified in sandbox.
- Paywall + Settings MEMBERSHIP section shipped in the design system, honest copy, visible restore, no dark patterns.
- The full FREE seam is functional with `isPro == false`; all unit/widget tests green; manual sandbox matrix passed.
- SOW-07/09/10 can gate purely by calling `requiresPro` / `ProGate` — no other SOW reads entitlement state directly.

**App Store Connect product setup notes (one-time, outside the codebase):**
- Create **Non-Consumable** `pro_lifetime`, price tier ≈ $29.99; localized display name/description.
- Create **Auto-Renewable Subscription** `pro_annual` in a subscription group, price ≈ $19.99/year; localized name/description; no intro offer at launch.
- Fill the **Subscription/IAP review** metadata + screenshot of the paywall; attach a **Privacy Policy URL** and **Terms (EULA)** — required for auto-renewable subscriptions (guideline 3.1.2).
- Create at least one **Sandbox Tester** Apple ID for testing.

**Positioning claim this unlocks:** the testable trust claim **"One-time purchase, honored forever. No feature ever removed."** from [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) becomes literally true and demonstrable in the product — a claim no incumbent (Strong, StrongLifts, GymStreak, Juggernaut) can make.

**Update [02-roadmap.md](../02-roadmap.md):** flip SOW-06 status to `🟦 In progress` on start, `✅ Shipped` on completion; confirm the roadmap's Phase-1 note "confirm progress charts / RIR field stay free when monetization lands" is satisfied by the seam table here. SOW-07 may then begin.
