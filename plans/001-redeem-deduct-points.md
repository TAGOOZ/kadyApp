# Plan 001: Deduct redeemed points at checkout — make `applyRedemption` reachable

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 0c1e59d..HEAD -- lib/domain/loyalty_rules.dart lib/domain/loyalty_controller.dart lib/ui/cart/checkout_screen.dart test/unit/loyalty_rules_test.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW–MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0c1e59d`, 2026-08-23

## Why this matters

Checkout lets a Customer with enough Points tick a redemption box ("استخدم 200 نقطة → مشروب مجاني"), zeroes the drink line on the paid total, and encodes `[REDEEMED:{type}:{cost}]` into the order notes — but **the Points are never deducted from anywhere**. The pure function that performs the deduction (`applyRedemption`) exists and is unit-tested, yet has zero call sites. A customer can redeem on every single order forever while keeping their balance: direct revenue loss on every order with ≥200 points, and staff see a REDEEMED note nothing enforces. Fixing this makes the loyalty economy's most expensive reward actually cost what the catalog says it costs.

## Current state

Relevant files:

- `lib/domain/loyalty_rules.dart` — pure loyalty math; contains the orphaned deduction function (lines 239–254).
- `lib/domain/loyalty_controller.dart` — Riverpod notifier that credits orders exactly once; `creditProcessedOrder` only ever ADDS points (lines 194–262).
- `lib/ui/cart/checkout_screen.dart` — checkout submit flow; builds the `[REDEEMED:…]` notes prefix and fires crediting (lines 135–171).
- `test/unit/loyalty_rules_test.dart` — existing tests incl. an `applyRedemption` group (line 389+).
- `test/widget/checkout_redemption_test.dart` — widget tests asserting notes prefix + discounted subtotal but never balance movement.

Excerpts verified at commit `0c1e59d`:

`lib/domain/loyalty_rules.dart:241-243` — defined, never called anywhere in `lib/`:

```dart
/// Spends the Points for [r]. Vouchers are NOT touched — redemption pays with
/// Points directly; Vouchers remain granted rewards awaiting staff use.
LoyaltyState applyRedemption(LoyaltyState s, Redemption r) {
  return s.copyWith(points: math.max(0, s.points - r.costPts));
}
```

`lib/ui/cart/checkout_screen.dart:135-171` — submission encodes the prefix, then calls ONLY the earn path:

```dart
    // Redemption rides as a notes prefix — `[REDEEMED:{type}:{cost}]` — so no
    // schema change is needed (accepted trade-off, see slice report).
    final draftNotes = draftState.notes.trim();
    final notes = [
      if (redemption != null)
        '[REDEEMED:${redemption.type.key}:${redemption.costPts}]',
      if (draftNotes.isNotEmpty) draftNotes,
    ].join(' ');
    ...
      unawaited(ref
          .read(loyaltyProvider.notifier)
          .creditProcessedOrder(
            orderId: placed.id,
            subtotalEgp: subtotalEgp,   // already AFTER the free-drink discount
            dineIn: mode == OrderMode.dineIn,
          ));
```

Note: `_submit` receives `subtotalEgp: subtotalAfterRedemption` from `build()` (checkout_screen.dart:381) and `redemption: redeemed ? redemption : null` (:384) — the data needed for deduction is already at the call site; it just isn't forwarded into crediting.

`lib/domain/loyalty_controller.dart:194-262` — `creditProcessedOrder({required String orderId, required int subtotalEgp, required bool dineIn})`. Inside its try block it: reads the server row into `base`, checks `alreadyProcessed(base, orderId)` (idempotency guard), computes `earned = earnedFor(...)`, applies pure `creditOrder(...)` + `markProcessed(...)`, sets `state = next` optimistically, then persists the whole row best-effort (`_persist`-style UPDATE filtered by phone). Any exception → catch swallows ("Offline policy: optimistic local state stands"). Because Supabase is not initialized under `flutter test`, the persist fails silently and the optimistic state stands — this is exactly how existing controller-level behavior is testable without network.

Conventions to follow:

- Pure decision math lives in `lib/domain/loyalty_rules.dart` (no Riverpod/Supabase imports); the controller loads/persists. See header comment of `loyalty_rules.dart:1-9`. Match it: put any new combined logic there as a pure function.
- Strings via catalogs keyed `AppLang`; no new user-visible strings are needed for this plan.
- Domain vocabulary: use CONTEXT.md terms (Points, Voucher, redemption) in names/comments.

## Commands you will need

| Purpose   | Command                    | Expected on success                                  |
|-----------|----------------------------|------------------------------------------------------|
| Analyze   | `flutter analyze`          | `No issues found!`                                    |
| All tests | `flutter test`             | ends `All tests passed!` (baseline +277 at plan time) |
| One file  | `flutter test test/unit/loyalty_rules_test.dart` | `All tests passed!`       |

(Baseline recorded at commit `0c1e59d`: analyze prints exactly `No issues found!`; full suite prints `+277: All tests passed!`.)

## Scope

**In scope** (the only files you should modify):

- `lib/domain/loyalty_rules.dart` (add one pure function)
- `lib/domain/loyalty_controller.dart` (extend one method signature + one line of math)
- `lib/ui/cart/checkout_screen.dart` (forward one argument)
- `test/unit/loyalty_rules_test.dart` (new tests)
- `test/widget/checkout_redemption_test.dart` (one strengthened assertion)

**Out of scope** (do NOT touch):

- `supabase/migrations/**` — no server-side enforcement in this plan; the RLS own-row cheat vector is a documented ADR-0007 trade-off.
- `lib/data/repos/driver_orders_repository.dart` `stripRedeemedPrefix` — display-side stripping must keep working unchanged.
- Any change to the `[REDEEMED:{type}:{cost}]` notes format — driver/staff screens parse it by regex `^\[REDEEMED:[^\]]*\]\s*`.

## Git workflow

- Branch: `advisor/001-redeem-deduct-points`
- Commit per step; message style matches repo history (conventional-ish, e.g. `fix(007): deduct redeemed points through creditProcessedOrder`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the combined pure function in `loyalty_rules.dart`

Below `applyRedemption` add:

```dart
/// Full post-checkout transition for ONE processed order that may carry a
/// checkout redemption: spends [r]'s Points first, then credits [earned]
/// against the discounted spend, marks the order processed. Pure — used by
/// LoyaltyController.creditProcessedOrder so deduction and earn land in a
/// single guarded state transition (and therefore a single persist).
LoyaltyState creditRedeemedOrder(
  LoyaltyState s, {
  required Redemption? redemption,
  required int earned,
  required int subtotalEgp,
  int stampMinSpendEgp = kStampMinSpendEgp,
}) {
  var next = redemption == null ? s : applyRedemption(s, redemption);
  next = creditOrder(
    next,
    earned: earned,
    subtotalEgp: subtotalEgp,
    stampMinSpendEgp: stampMinSpendEgp,
  );
  return next;
}
```

(`Redemption`/`RedemptionType` are declared lower in the same file — place this function AFTER them, near `drinkLineDiscountEgp`.)

**Verify**: `flutter analyze` → `No issues found!`

### Step 2: Thread `redemption` through `creditProcessedOrder`

In `lib/domain/loyalty_controller.dart`:

1. Import is already present (`loyalty_rules.dart`) — no import changes.
2. Change the signature to add an optional parameter:

```dart
  Future<void> creditProcessedOrder({
    required String orderId,
    required int subtotalEgp,
    required bool dineIn,
    Object? redemption, // Redemption? — typed below once you add the import alias
  }) async {
```

Use the real type `Redemption?` from `loyalty_rules.dart` (it is already imported; write `Redemption? redemption` directly).

3. Replace the two consecutive pure-math calls inside the guarded block

```dart
      var next = creditOrder(
        base,
        earned: earned,
        subtotalEgp: subtotalEgp,
        stampMinSpendEgp: config.stampMinSpendEgp,
      );
      next = markProcessed(next, orderId);
```

with

```dart
      var next = creditRedeemedOrder(
        base,
        redemption: redemption,
        earned: earned,
        subtotalEgp: subtotalEgp,
        stampMinSpendEgp: config.stampMinSpendEgp,
      );
      next = markProcessed(next, orderId);
```

Everything else (server-row read, idempotency guard, optimistic set, best-effort persist) stays byte-identical. The deduction now rides the same `processed_orders` guard, so a retried call can never deduct twice.

**Verify**: `flutter analyze` → `No issues found!`

### Step 3: Forward the redemption from checkout

In `lib/ui/cart/checkout_screen.dart`, extend the `unawaited(...)` crediting call (~line 165) with the already-computed value:

```dart
      unawaited(ref
          .read(loyaltyProvider.notifier)
          .creditProcessedOrder(
            orderId: placed.id,
            subtotalEgp: subtotalEgp,
            dineIn: mode == OrderMode.dineIn,
            redemption: redeemed ? redemption : null,
          ));
```

(`redeemed` and `redemption` are in scope in `_submit` — they arrive as parameters.)

**Verify**: `flutter analyze` → `No issues found!` && `flutter test test/widget/checkout_redemption_test.dart` → all pass (existing assertions on notes prefix/subtotal must still hold).

### Step 4: Tests

Unit tests in `test/unit/loyalty_rules_test.dart`, new group after the existing `applyRedemption` group (model structure after the neighboring groups):

```dart
  group('creditRedeemedOrder — deduction rides the credit', () {
    test('free drink: 200 pts spent, earn added on discounted spend', () {
      final s = creditRedeemedOrder(
        _state(points: 250),
        redemption: const Redemption(type: RedemptionType.freeDrink, costPts: 200),
        earned: 2,
        subtotalEgp: 15,
      );
      expect(s.points, 52);          // 250 − 200 + 2
      expect(s.lifetimePoints, ...); // lifetime grows by EARN only (see note)
      expect(s.processedOrders, contains('o1')); // when orderId passed via markProcessed path
    });
    test('null redemption behaves exactly like creditOrder', () { ... });
    test('balance floors at 0 when cost exceeds balance', () { ... });
  });
```

Write real expectations (compute them by hand): `lifetimePoints` increases by `earned` only — `applyRedemption` touches only `points` (verified: loyalty_rules.dart:242). If you find yourself wanting `markProcessed` inside the pure function, stop: keep `markProcessed` called by the controller exactly as today, and drop the `processedOrders` assertion or assert it via the controller wiring instead.

Widget-test strengthening in `test/widget/checkout_redemption_test.dart`: in the existing submit test ("submit encodes [REDEEMED] …"), after `pumpAndSettle` add an assertion that the remaining-points preview text `رصيدك بعد الاستخدام: 0 نقطة` is gone AND document (comment only) that server-balance deduction is covered by the unit tests above — the widget test uses `_FixedLoyalty` which bypasses real state transitions, so do not attempt to assert post-submit balance there.

**Verify**: `flutter test test/unit/loyalty_rules_test.dart` → all pass including ≥3 new tests; then `flutter test` → `All tests passed!` with count ≥ baseline+3.

## Test plan

- New unit cases listed in Step 4: happy-path deduction, null-redemption equivalence, floor-at-zero.
- Pattern source: existing `applyRedemption` group in the same file (uses `_state(...)` helper).
- Verification: `flutter test` → `All tests passed!`, test count strictly greater than the +277 baseline.

## Done criteria

- [ ] `flutter analyze` exits 0 printing `No issues found!`
- [ ] `flutter test` exits 0; ≥3 new `creditRedeemedOrder` tests exist and pass
- [ ] `grep -rn "applyRedemption" lib/` shows it referenced from `creditRedeemedOrder` (previously zero callers)
- [ ] `grep -n "redemption:" lib/ui/cart/checkout_screen.dart` shows the forwarded argument in the crediting call
- [ ] No files outside the in-scope list modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- The excerpts above no longer match (files drifted past `0c1e59d`).
- You find `applyRedemption` already wired somewhere (finding fixed independently) — report instead of re-planning.
- Making the widget test assert real balance mutation requires changing `_FixedLoyalty`'s override semantics — out of scope, report back.
- The dedup/idempotency guard (`alreadyProcessed`) moves or changes shape during your edit.

## Maintenance notes

- When the Edge Function for server-side crediting lands (ADR-0007 follow-up), mirror this deduction server-side — until then the client remains the only enforcer, which is the documented MVP posture.
- The `[REDEEMED:…]` notes regex in `driver_orders_repository.dart:102` and any staff parsing must survive any future format tweak; a reviewer should grep both when touching redemption encoding.
- Reviewer focus: confirm the deduction happens INSIDE the `alreadyProcessed` guard (no double-deduct on retry) and that `lifetimePoints` is unaffected by redemption cost.
