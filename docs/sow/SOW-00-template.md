# SOW-NN — <Feature Name>

> **Status:** ⬜ Not started · **Phase:** <0/1/2/3> · **Tier:** <Free / Paid / Infra>
> **Owner:** berke · **Est. size:** <S / M / L>
> **Strategic rationale:** <one line — which rival gap or trust claim this closes; link [01-strategy-and-positioning.md](../01-strategy-and-positioning.md) / [00-competitive-analysis.md](../00-competitive-analysis.md)>

Every SOW in this folder follows this structure. Keep it grounded in real files (cite `lib/...` paths), match the existing architecture (Riverpod tri-layer, sqflite migrations, the design system), and respect the non-negotiables in [README.md](../README.md).

---

## 1. Goal & Constraints
- **What this delivers** (1-3 bullets, user-visible).
- **Why now** (the competitive/trust reason).
- **Hard constraints** (must stay free? must work on watch? no new dependency? minimalism guardrail?).
- **Non-goals** (what this SOW deliberately does NOT do).

## 2. Competitive context
- Which rivals have this, how, and where they fall short. What "match" looks like and what "surpass" looks like for us.

## 3. Locked decisions
| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | … | … | … |

## 4. Design & UX
- Screens/sheets touched, interaction flow, and how it maps to the design system (`LsType`, `LsAccent`, `LsSpace`, `r3`). ASCII mock where useful. Watch behavior if applicable.

## 5. Data & schema changes
- New tables/columns + the **migration** (mirror the cumulative pattern in `lib/core/db/migrations.dart`, bump version in `database.dart`). Settings/flags to add (the `settings_repository.dart` pattern). Watch bridge / Pigeon contract changes if any. **If none: say "No schema change."**

## 6. Implementation plan
- Ordered steps by layer: `domain/` → `data/` (DAO) → `application/` (controller/provider) → `presentation/` (UI) → watch (Swift) if applicable. Name the specific files to add/modify.

## 7. Acceptance criteria
- [ ] Concrete, testable checkboxes a reviewer can verify.

## 8. Testing
- Unit tests (in-memory sqflite via `sqflite_ffi`, mirror `test/dao_test.dart` / `test/queries_test.dart` / `test/workout_progress_test.dart`), widget tests, and any manual matrix (esp. watch + reliability).

## 9. Risks & mitigations
| Risk | Likelihood | Mitigation |
|---|---|---|

## 10. Definition of done
- The shippable bar + the positioning claim it unlocks + what to update in [02-roadmap.md](../02-roadmap.md).
