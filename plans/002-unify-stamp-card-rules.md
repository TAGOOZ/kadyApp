# Plan 002: Unify stamp-card math behind one pure rule

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 0c1e59d..HEAD -- lib/domain/loyalty_rules.dart lib/domain/loyalty_controller.dart lib/data/repos/staff_orders_repository.dart lib/data/repos/customer_lookup_repository.dart test/unit/loyalty_rules_test.dart test/unit/staff_orders_repository_test.dart test/unit/customer_lookup_repository_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none (independent of plan 001; both touch `loyalty_rules.dart` — land sequentially and re-run its drift check)
- **Category**: bug / tech-debt
- **Planned at**: commit `0c1e59d`, 2026-08-23

## Why this matters

"Add one stamp to a card" is implemented three different ways that disagree:

1. Order credit (`creditOrder`) parks a FULL card at 10/10 and completes it only when an 11th qualifying visit arrives (test-pinned).
2. Quest/stamp grants (`grantStamps` in the controller) complete the card at exactly 10 and reset to 0.
3. Staff check-in (`registerVisit`, staff board + lookup repos) writes a raw `current + 1` with no wrap at all — stamps can reach 11, 12, … with no voucher ever granted.

Same domain rule (CONTEXT.md: "Completing a card grants a fixed reward"), three behaviors depending on which path touched the card. The home widget caption `{stamps} / 10 visits → Free snack` promises completion at 10 for everyone. Consolidating on ONE pure function removes the drift class entirely: future rule changes become one-line diffs instead of hunts through three files.

## Current state

Relevant files:

- `lib/domain/loyalty_rules.dart:122-159` — canonical pure `creditOrder` (order path).
- `lib/domain/loyalty_controller.dart:354-377` — `grantStamps` re-implements wrap logic inline.
- `lib/data/repos/staff_orders_repository.dart:519-537` — check-in stamp attempt, raw increment.
- `lib/data/repos/customer_lookup_repository.dart:558-573` — duplicate of the same raw-increment block.
- `lib/ui/home/widgets/stamp_card_widget.dart:36` + `lib/core/l10n/strings_home.dart:170` — caption `{stamps} / 10 visits → Free snack`.
- `test/unit/loyalty_rules_test.dart:200-251` — tests pinning `creditOrder` semantics.

Excerpts verified at commit `0c1e59d`:

Canonical (test-pinned) semantics — `lib/domain/loyalty_rules.dart:133-149`:

```dart
  if (subtotalEgp >= stampMinSpendEgp) {
    final newStamps = stamps + 1;
    if (newStamps > 10) {
      completedCards += 1;
      vouchers = [...vouchers, Voucher(type: VoucherType.freeSnack, ...)];
      stamps = newStamps % 10 == 0 ? 10 : newStamps % 10;
    } else {
      stamps = newStamps;
    }
    if (stamps % 3 == 0) spinnerTokens += 1;
  }
```

Pinned by `test/unit/loyalty_rules_test.dart:201-206`:

```dart
    test('9→10 fills the card WITHOUT completing it', () {
      final s = creditOrder(_state(stamps: 9), earned: 5, subtotalEgp: 80);
      expect(s.stamps, 10);
      expect(s.completedCards, 0);
      expect(s.vouchers, isEmpty);
```

Divergent copy #1 — `lib/domain/loyalty_controller.dart:362-374` (`grantStamps`): completes at `newStamps >= 10` and resets to `newStamps - 10` (i.e. 0), then separately grants a spinner token when post-wrap `stamps % 3 == 0 && stamps > 0`. Different completion threshold AND different reset value than `creditOrder`.

Divergent copy #2 — `lib/data/repos/staff_orders_repository.dart:526-533`:

```dart
      if (input.spendEgp >= threshold) {
        final current = await _db.fetchStamps(input.phone);
        if (current == null) {
          loyaltyPending = true; // row not visible — cannot verify
        } else {
          await _db.updateStamps(input.phone, current + 1);
        }
      }
```

No wrap, no completed-card, no voucher/token. `customer_lookup_repository.dart:562-568` is the same block duplicated. Note: under current RLS this write degrades to `loyaltyPending` for real staff sessions (documented pending state until an Edge Function exists) — but the code path runs whenever RLS permits, and it is the semantics an Edge Function would inherit.

Conventions to follow:

- Pure rules live in `loyalty_rules.dart`; controller/repos load & persist. Match the existing header contract (`loyalty_rules.dart:1-9`).
- Keep every existing passing test green — they are the behavioral spec.
- CONTEXT.md vocabulary in names/comments: Stamp, Stamp Card, qualifying Visit, Spinner Token, Voucher.

## Commands you will need

| Purpose   | Command                    | Expected on success                                  |
|-----------|----------------------------|------------------------------------------------------|
| Analyze   | `flutter analyze`          | `No issues found!`                                    |
| All tests | `flutter test`             | ends `All tests passed!` (baseline +277 at plan time) |
| Unit only | `flutter test test/unit`   | all pass                                              |

## Scope

**In scope** (the only files you should modify):

- `lib/domain/loyalty_rules.dart` (add one pure function)
- `lib/domain/loyalty_controller.dart` (`grantStamps` body becomes a delegate)
- `lib/data/repos/staff_orders_repository.dart` (stamp-attempt block uses shared math)
- `lib/data/repos/customer_lookup_repository.dart` (same)
- `test/unit/loyalty_rules_test.dart`, `test/unit/staff_orders_repository_test.dart`, `test/unit/customer_lookup_repository_test.dart` (new cases)

**Out of scope** (do NOT touch):

- `creditOrder` itself and ALL its existing tests — its behavior is the canonical spec being spread, not changed.
- The UI caption or any strings catalog — whether a card should complete AT 10 vs ON THE VISIT AFTER 10 is a product question; do not resolve it here.
- Any SQL/migration or Edge Function work.
- `quest_state_store.dart` pending-grants queue.

## Git workflow

- Branch: `advisor/002-unify-stamp-rules`
- Commit per step; style like `refactor(007): single stamp-wrap rule behind grantStampsPure`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add `grantStampsPure` to `loyalty_rules.dart`

New pure function replicating EXACTLY the wrap/threshold/voucher/token semantics of `creditOrder`'s stamp branch, but taking a stamp COUNT instead of reading `subtotalEgp`:

```dart
/// Applies [n] already-qualifying stamps using the same card rules as
/// [creditOrder]: park at 10, complete on the NEXT qualifying stamp
/// (>10 → completedCards+1, free-snack Voucher, wrapped position), spinner
/// token on every post-wrap multiple of 3. Single source of truth so order
/// credit, quest grants and staff check-ins can never diverge again.
LoyaltyState grantStampsPure(
  LoyaltyState s,
  int n, {
  DateTime? nowUtc, // injectable clock for voucher timestamps (tests)
}) 
```

Implementation requirement: extract the per-stamp transition from `creditOrder`'s loop into a private helper `_applyQualifyingStamp(...)` used by BOTH `creditOrder` and `grantStampsPure`, so the two cannot drift again. `creditOrder` keeps its exact public signature and semantics. Use `nowUtc ?? DateTime.now().toUtc()` for the voucher timestamp (matches current call shape at loyalty_rules.dart:141).

**Verify**: `flutter analyze` → `No issues found!`; `flutter test test/unit/loyalty_rules_test.dart` → all pass UNCHANGED (proves the extraction was behavior-preserving).

### Step 2: Delegate `grantStamps` in the controller

Replace the loop in `LoyaltyController.grantStamps` (loyalty_controller.dart:354-377) with:

```dart
  Future<void> grantStamps(int n) async {
    if (n <= 0) return;
    state = grantStampsPure(state, n);
    await _persist();
  }
```

Note the deliberate semantic change: quest-granted stamps now follow the SAME park-at-10/completion-on-next rule as orders. Update any test asserting old `>=10` reset behavior if one exists (search `grantStamps` under `test/`); add a case pinning: stamps 8 → grant 2 → lands at 10, `completedCards` unchanged; one more → completes card, wraps to 1.

**Verify**: `flutter analyze` → `No issues found!`; `flutter test` → all pass.

### Step 3: Route both check-in blocks through the shared math

In BOTH `staff_orders_repository.dart` (block at :523-536) and `customer_lookup_repository.dart` (block at :559-572), replace

```dart
          await _db.updateStamps(input.phone, current + 1);
```

with computing the wrapped count via the shared rule and writing it:

```dart
          final next = grantStampsPure(LoyaltyState(stamps: current), 1);
          await _db.updateStamps(input.phone, next.stamps);
```

Rationale: the direct write remains limited to what the column-level update can express today (stamps only — vouchers/tokens stay on the documented pending path), but the VALUE written now respects card wrapping, so no `11+` counts can be persisted even when RLS someday allows the write. Both repos import `loyalty_rules.dart`/`loyalty_controller.dart` types — add the required import (`../../domain/loyalty_controller.dart` exposes `LoyaltyState`; `../../domain/loyalty_rules.dart` exposes `grantStampsPure`) following each file's existing import ordering.

**Verify**: `flutter analyze` → `No issues found!`; `flutter test test/unit/staff_orders_repository_test.dart test/unit/customer_lookup_repository_test.dart` → all pass. Add one fake-based case per repo: `fetchStamps → 10`, spend ≥ threshold → `updateStamps` called with `10` (parked, NOT 11).

### Step 4: Pin the unified rule with unit tests

In `test/unit/loyalty_rules_test.dart`, new group `grantStampsPure` covering: n ≤ 0 no-op; 9→10 parks without completing; 10→(next)→11-style overflow completes card + freeSnack voucher + wraps to 1; every-3rd token on post-wrap position; input purity. Model after the neighboring `creditOrder — card completion edges` group (:200).

**Verify**: `flutter test` → `All tests passed!`, count > baseline.

## Test plan

- New cases listed in Steps 2–4 (controller delegation, both repo blocks, pure-function matrix).
- Structural pattern: existing groups in `test/unit/loyalty_rules_test.dart`; repo fakes modeled on those files' existing fake `StaffOrdersDb` / `CustomerLookupDb` implementations.
- Verification: `flutter test` exits 0; total count ≥ baseline + 6.

## Done criteria

- [ ] `flutter analyze` exits 0 printing `No issues found!`
- [ ] `flutter test` exits 0; original `creditOrder` group untouched and green
- [ ] `grep -n "current + 1" lib/data/repos/*.dart` returns no matches
- [ ] `grep -rn "newStamps >= 10\|stamps - 10" lib/domain/loyalty_controller.dart` returns no matches (logic moved to the shared pure function)
- [ ] No files outside the in-scope list modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- Excerpts above don't match the live tree (drift past `0c1e59d`).
- Extracting the shared helper forces ANY change to `creditOrder`'s observable outputs — report; the extraction must be purely mechanical.
- A test outside the in-scope list fails because it pinned `grantStamps`' old `>=10` semantics AND updating it would change a widget expectation about vouchers/badges — report instead of editing broadly.
- You discover `updateStamps` callers relying on raw increment values elsewhere.

## Maintenance notes

- When the Edge Function for check-in crediting lands, port `grantStampsPure`'s rule to SQL/Deno — it is now the single documented spec.
- If product decides cards should complete AT 10, change ONLY `creditOrder` + `grantStampsPure`'s shared helper and the two pinned tests; everything else follows.
- Reviewer focus: `creditOrder` diff must be zero (behavioral spec); confirm the lookup/stamp blocks still degrade to `loyaltyPending` on RLS denial exactly as before.
