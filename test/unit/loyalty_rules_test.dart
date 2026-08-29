// Exhaustive unit tests for the pure loyalty rules (#007 / FEATURES §4).
// No network, no Riverpod, no Supabase — in-memory LoyaltyState only.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
import 'package:kady_app/domain/loyalty_rules.dart';

LoyaltyState _state({
  int points = 0,
  int lifetime = 0,
  int stamps = 0,
  int cards = 0,
  int spinner = 0,
  List<Voucher> vouchers = const [],
  List<String> processed = const [],
}) =>
    LoyaltyState(
      points: points,
      lifetimePoints: lifetime,
      stamps: stamps,
      completedCards: cards,
      spinnerTokens: spinner,
      vouchers: vouchers,
      processedOrders: processed,
    );

void main() {
  group('earnedFor — rounding matrix (round half-up on final value)', () {
    test('90 pickup → 9', () {
      expect(
        earnedFor(
          subtotalEgp: 90,
          dineIn: false,
          pointsPer10: kPointsPer10Egp,
          dineInMultiplier: kDineInMultiplier,
          doubleWindow: false,
        ),
        9,
      );
    });

    test('90 dine-in → 9×1.1=9.9 → 10', () {
      expect(
        earnedFor(
          subtotalEgp: 90,
          dineIn: true,
          pointsPer10: kPointsPer10Egp,
          dineInMultiplier: kDineInMultiplier,
          doubleWindow: false,
        ),
        10,
      );
    });

    test('95 pickup → 9.5 → 10', () {
      expect(
        earnedFor(
          subtotalEgp: 95,
          dineIn: false,
          pointsPer10: kPointsPer10Egp,
          dineInMultiplier: kDineInMultiplier,
          doubleWindow: false,
        ),
        10,
      );
    });

    test('double window: 90 pickup → 18 · 90 dine-in → 19.8 → 20', () {
      expect(
        earnedFor(
          subtotalEgp: 90,
          dineIn: false,
          pointsPer10: kPointsPer10Egp,
          dineInMultiplier: kDineInMultiplier,
          doubleWindow: true,
        ),
        18,
      );
      // 90 × 1/10 × 1.1 × 2 = 19.8 → 20 (half-up on the FINAL value).
      expect(
        earnedFor(
          subtotalEgp: 90,
          dineIn: true,
          pointsPer10: kPointsPer10Egp,
          dineInMultiplier: kDineInMultiplier,
          doubleWindow: true,
        ),
        20,
      );
    });

    test('fraction floors below half: 94 → 9', () {
      expect(
        earnedFor(
          subtotalEgp: 94,
          dineIn: false,
          pointsPer10: kPointsPer10Egp,
          dineInMultiplier: kDineInMultiplier,
          doubleWindow: false,
        ),
        9,
      );
    });

    test('custom points_per_10egp scales the base', () {
      // Admin doubles earn rate: 100 EGP pickup → 100×2/10 = 20.
      expect(
        earnedFor(
          subtotalEgp: 100,
          dineIn: false,
          pointsPer10: 2,
          dineInMultiplier: kDineInMultiplier,
          doubleWindow: false,
        ),
        20,
      );
    });

    test('zero subtotal earns nothing', () {
      expect(
        earnedFor(
          subtotalEgp: 0,
          dineIn: true,
          pointsPer10: kPointsPer10Egp,
          dineInMultiplier: kDineInMultiplier,
          doubleWindow: true,
        ),
        0,
      );
    });
  });

  group('creditOrder — points & qualifying visit', () {
    test('adds earned to points and lifetime; tier follows lifetime', () {
      final s = creditOrder(_state(lifetime: 1995), earned: 10, subtotalEgp: 95);
      expect(s.points, 10);
      expect(s.lifetimePoints, 2005);
      expect(s.tier, Tier.silver);
    });

    test('subtotal ≥ 50 qualifies → +1 stamp', () {
      final s = creditOrder(_state(), earned: 5, subtotalEgp: 50);
      expect(s.stamps, 1);
    });

    test('subtotal < 50 does NOT qualify — no stamp, no token', () {
      final s = creditOrder(_state(stamps: 2), earned: 4, subtotalEgp: 49);
      expect(s.stamps, 2);
      expect(s.spinnerTokens, 0);
    });

    test('non-qualifying order still earns points', () {
      final s = creditOrder(_state(points: 3), earned: 4, subtotalEgp: 40);
      expect(s.points, 7);
      expect(s.stamps, 0);
    });

    test('custom stamp threshold honored from config', () {
      final s = creditOrder(
        _state(),
        earned: 2,
        subtotalEgp: 30,
        stampMinSpendEgp: 30,
      );
      expect(s.stamps, 1);
    });
  });

  group('creditOrder — every 3rd stamp grants a Spinner Token', () {
    test('2→3 stamps: +1 spinner token', () {
      final s = creditOrder(_state(stamps: 2), earned: 5, subtotalEgp: 60);
      expect(s.stamps, 3);
      expect(s.spinnerTokens, 1);
    });

    test('8→9 stamps (9 % 3): second token of a card', () {
      final s = _state(stamps: 8, spinner: 2);
      final next = creditOrder(s, earned: 5, subtotalEgp: 60);
      expect(next.stamps, 9);
      expect(next.spinnerTokens, 3);
    });

    test('5→6 stamps: 6 is a multiple of 3 → +1 spinner token', () {
      final s = creditOrder(_state(stamps: 5), earned: 5, subtotalEgp: 60);
      expect(s.stamps, 6);
      expect(s.spinnerTokens, 1);
    });

    test('wrap lands on 1 → no spurious token', () {
      final s = creditOrder(
        _state(stamps: 10, cards: 1),
        earned: 5,
        subtotalEgp: 60,
      );
      expect(s.completedCards, 2);
      expect(s.stamps, 1);
      expect(s.spinnerTokens, 0);
    });
  });

  group('creditOrder — card completion edges', () {
    test('9→10 REACHES 10: card completes and resets to 0', () {
      // Plan 002 unification: park-at-10 retired — a full card grants the
      // reward immediately (canonical rule = reaching 10 completes & resets,
      // matching grantStamps / FEATURES §4 "full card → fixed reward").
      final s = creditOrder(_state(stamps: 9), earned: 5, subtotalEgp: 80);
      expect(s.stamps, 0);
      expect(s.completedCards, 1);
      expect(s.vouchers.single.type, VoucherType.freeSnack);
    });

    test('10→11 wraps: card+1, free-snack voucher, new card at 1', () {
      final s = creditOrder(
        _state(stamps: 10),
        earned: 5,
        subtotalEgp: 80,
      );
      expect(s.completedCards, 1);
      expect(s.stamps, 1);
      expect(s.vouchers.single.type, VoucherType.freeSnack);
    });

    test('existing vouchers preserved when granting the snack voucher', () {
      final existing = Voucher(
        type: VoucherType.freeDrink,
        grantedAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );
      final s = creditOrder(
        _state(stamps: 10, vouchers: [existing]),
        earned: 5,
        subtotalEgp: 80,
      );
      expect(s.vouchers, hasLength(2));
      expect(s.vouchers.first.type, VoucherType.freeDrink);
      expect(s.vouchers.last.type, VoucherType.freeSnack);
    });

    test('defensive wrap: overflow landing on a decade shows a full card', () {
      // Corrupted row with stamps=19 → 20 ≥ 10 → one completion, remainder
      // wraps by −10 to 10 (never negative, never 11+).
      final s = LoyaltyState(stamps: 19);
      final next = creditOrder(s, earned: 5, subtotalEgp: 80);
      expect(next.completedCards, 1);
      expect(next.stamps, 10);
      // 10 % 3 ≠ 0 → no token from the wrapped position.
      expect(next.spinnerTokens, 0);
    });

    test('creditOrder is pure — input state untouched', () {
      final before = _state(points: 10, lifetime: 10, stamps: 2);
      creditOrder(before, earned: 5, subtotalEgp: 60);
      expect(before.points, 10);
      expect(before.lifetimePoints, 10);
      expect(before.stamps, 2);
      expect(before.spinnerTokens, 0);
    });
  });

  group('grantStampsPure — the unified card rule (plan 002)', () {
    test('n ≤ 0 is a no-op', () {
      final s = _state(stamps: 5, cards: 1, spinner: 1);
      for (final n in [0, -1, -7]) {
        final next = grantStampsPure(s, n);
        expect(next.stamps, 5);
        expect(next.completedCards, 1);
        expect(next.spinnerTokens, 1);
        expect(next.vouchers, isEmpty);
      }
    });

    test('9→10 REACHES 10: card completes, resets to 0, free-snack voucher',
        () {
      final s = grantStampsPure(
        _state(stamps: 9),
        1,
        nowUtc: DateTime.parse('2026-08-23T10:00:00Z'),
      );
      expect(s.stamps, 0);
      expect(s.completedCards, 1);
      expect(s.vouchers.single.type, VoucherType.freeSnack);
      // Position 0 is not an every-3rd position — no token from completing.
      expect(s.spinnerTokens, 0);
      // Injected clock lands on the voucher timestamp.
      expect(
        s.vouchers.single.grantedAt,
        DateTime.parse('2026-08-23T10:00:00Z'),
      );
    });

    test('8 → grant 2 → completes & resets (quest-grant edge)', () {
      // Plan 002 unification pin: quest-granted stamps follow the SAME
      // reaching-10-completes-and-resets rule as order credit.
      final s = grantStampsPure(_state(stamps: 8), 2);
      expect(s.stamps, 0);
      expect(s.completedCards, 1);
      expect(s.vouchers.single.type, VoucherType.freeSnack);
    });

    test('legacy full row 10 → one more completes again, wraps to 1', () {
      final s = grantStampsPure(_state(stamps: 10, cards: 1), 1);
      expect(s.completedCards, 2);
      expect(s.stamps, 1);
      expect(s.spinnerTokens, 0); // 1 % 3 ≠ 0 — no spurious token
    });

    test('every-3rd token fires on post-wrap positions only', () {
      // From 8 with 2 tokens: 9 (token →3) · 10 completes → 0 · 1 · 2.
      final s = grantStampsPure(_state(stamps: 8, spinner: 2), 4);
      expect(s.stamps, 2);
      expect(s.completedCards, 1);
      expect(s.vouchers.single.type, VoucherType.freeSnack);
      expect(s.spinnerTokens, 3);
    });

    test('existing vouchers preserved; input state untouched', () {
      final existing = Voucher(
        type: VoucherType.freeDrink,
        grantedAt: DateTime.parse('2026-01-01T00:00:00Z'),
      );
      final before = _state(stamps: 8, vouchers: [existing]);
      final s = grantStampsPure(before, 2);
      expect(s.vouchers, hasLength(2));
      expect(s.vouchers.first.type, VoucherType.freeDrink);
      expect(s.vouchers.last.type, VoucherType.freeSnack);
      // Purity.
      expect(before.stamps, 8);
      expect(before.completedCards, 0);
      expect(before.spinnerTokens, 0);
      expect(before.vouchers, hasLength(1));
    });

    test('identical inputs → identical states as creditOrder (unification)',
        () {
      // The whole point of plan 002: the order-credit path and the
      // grant path must produce identical stamp outcomes.
      const base = LoyaltyState(stamps: 8, spinnerTokens: 2, completedCards: 1);
      final viaCredit = creditOrder(base, earned: 5, subtotalEgp: 80);
      final viaGrant = grantStampsPure(base, 1);
      expect(viaGrant.stamps, viaCredit.stamps);
      expect(viaGrant.completedCards, viaCredit.completedCards);
      expect(viaGrant.spinnerTokens, viaCredit.spinnerTokens);
      // 8→9 completes nothing — voucher lists stay empty on BOTH paths.
      expect(viaGrant.vouchers, isEmpty);
      expect(viaCredit.vouchers, isEmpty);
      // …and a long grant matches repeated credits stamp-for-stamp
      // (voucher timestamps are wall-clock per call, so compare shape).
      var credited = base;
      for (var i = 0; i < 6; i++) {
        credited = creditOrder(credited, earned: 5, subtotalEgp: 80);
      }
      final granted6 = grantStampsPure(base, 6);
      expect(granted6.stamps, credited.stamps);
      expect(granted6.completedCards, credited.completedCards);
      expect(granted6.spinnerTokens, credited.spinnerTokens);
      expect(granted6.vouchers.length, credited.vouchers.length);
      expect(
        granted6.vouchers.map((v) => v.type),
        credited.vouchers.map((v) => v.type),
      );
    });
  });

  group('processed-orders guard list', () {
    test('alreadyProcessed detects members only', () {
      final s = _state(processed: ['o-1', 'o-2']);
      expect(alreadyProcessed(s, 'o-1'), isTrue);
      expect(alreadyProcessed(s, 'o-3'), isFalse);
    });

    test('markProcessed appends and caps at the newest 100', () {
      final seeded = _state(
        processed: [for (var i = 0; i < 100; i++) 'old-$i'],
      );
      final marked = markProcessed(seeded, 'new');
      expect(marked.processedOrders, hasLength(100));
      expect(marked.processedOrders.contains('new'), isTrue);
      expect(marked.processedOrders.contains('old-0'), isFalse); // oldest evicted
      expect(marked.processedOrders.first, 'old-1');
    });

    test('idempotent credit: same orderId twice = single effect', () {
      // The controller consults this guard BEFORE applying creditOrder, so
      // replaying the same order must leave state untouched after the first
      // application — verified here at the pure layer (no network).
      var s = const LoyaltyState();
      const orderId = 'order-abc';
      if (!alreadyProcessed(s, orderId)) {
        s = markProcessed(
          creditOrder(s, earned: 10, subtotalEgp: 95),
          orderId,
        );
      }
      final afterFirst = s;
      if (!alreadyProcessed(afterFirst, orderId)) {
        fail('guard list must contain the credited order id');
      }
      // Second delivery attempt: guard trips, no further mutation.
      expect(afterFirst.points, 10);
      expect(afterFirst.lifetimePoints, 10);
      expect(afterFirst.stamps, 1);
      expect(afterFirst.processedOrders, ['order-abc']);
    });

    test('LoyaltyState json round-trips processed_orders', () {
      final s = LoyaltyState.fromJson({
        'points': 5,
        'processed_orders': ['a', 'b'],
      });
      expect(s.processedOrders, ['a', 'b']);
    });
  });

  group('redeemable — eligibility matrix', () {
    test('null when nothing affordable', () {
      expect(
        redeemable(_state(points: 99), hasDrinkLine: true),
        isNull,
      );
      expect(
        redeemable(_state(points: 99), hasDrinkLine: false),
        isNull,
      );
      expect(
        redeemable(const LoyaltyState(), hasDrinkLine: true),
        isNull,
      );
    });

    test('120 pts with drink line → cheapest applicable is topping (100)',
        () {
      final r = redeemable(_state(points: 120), hasDrinkLine: true);
      expect(r!.type, RedemptionType.freeTopping);
      expect(r.costPts, 100);
    });

    test('160 pts without drink line → snack (150); topping needs a drink',
        () {
      final r = redeemable(_state(points: 160), hasDrinkLine: false);
      expect(r!.type, RedemptionType.freeSnack);
      expect(r.costPts, 150);
    });

    test('200 pts with drink line → flagship free drink at redeem floor',
        () {
      final r = redeemable(_state(points: 200), hasDrinkLine: true);
      expect(r!.type, RedemptionType.freeDrink);
      // max(redeem_min_points, reward_drink) — both seeded at 200.
      expect(r.costPts, kRewardDrinkPts);
    });

    test('199 pts with drink line → NOT enough for drink; falls to topping',
        () {
      final r = redeemable(_state(points: 199), hasDrinkLine: true);
      expect(r!.type, RedemptionType.freeTopping);
    });

    test('admin-raised redeem_min_points raises the drink gate', () {
      const raised = LoyaltyRulesConfig(redeemMinPoints: 300);
      // Drink gate = max(300, reward_drink 200) → 250 pts not enough for it;
      // the affordable topping tier still applies on a drink line.
      final below =
          redeemable(_state(points: 250), hasDrinkLine: true, config: raised);
      expect(below!.type, RedemptionType.freeTopping);
      final ok =
          redeemable(_state(points: 300), hasDrinkLine: true, config: raised);
      expect(ok!.type, RedemptionType.freeDrink);
      expect(ok.costPts, 300);
    });

    test('admin-lowered catalog costs flow through config', () {
      const cheap = LoyaltyRulesConfig(
        rewardToppingPts: 50,
        rewardSnackPts: 75,
        rewardDrinkPts: 90,
        redeemMinPoints: 90,
      );
      // No drink line → snack tier at 75 once affordable.
      expect(
        redeemable(_state(points: 80), hasDrinkLine: false, config: cheap)!
            .type,
        RedemptionType.freeSnack,
      );
      // Drink line present → cheapest applicable is topping at 50.
      expect(
        redeemable(_state(points: 55), hasDrinkLine: true, config: cheap)!.type,
        RedemptionType.freeTopping,
      );
    });

    test('isDrinkCategorySlug matches seeded hot/cold drinks only', () {
      expect(isDrinkCategorySlug('hot_drinks'), isTrue);
      expect(isDrinkCategorySlug('cold_drinks'), isTrue);
      expect(isDrinkCategorySlug('snacks'), isFalse);
      expect(isDrinkCategorySlug('specials'), isFalse);
    });

    test('isDrinkCategorySlug includes iced-espresso (0005)', () {
      expect(isDrinkCategorySlug('iced-espresso'), isTrue);
      expect(isDrinkCategorySlug('hot-drinks'), isTrue);
      expect(isDrinkCategorySlug('cold-drinks'), isTrue);
    });

    test('drinkLineDiscountEgp counts iced-espresso as drink', () {
      final discount = drinkLineDiscountEgp([
        (categorySlug: 'iced-espresso', lineTotalEgp: 85),
        (categorySlug: 'snacks', lineTotalEgp: 50),
      ]);
      expect(discount, 85);
    });
  });

  group('applyRedemption', () {
    test('spends points only — lifetime, stamps, vouchers untouched', () {
      final voucher = Voucher(
        type: VoucherType.freeSnack,
        grantedAt: DateTime.parse('2026-02-02T00:00:00Z'),
      );
      final s = _state(
        points: 250,
        lifetime: 250,
        stamps: 4,
        cards: 1,
        spinner: 1,
        vouchers: [voucher],
      );
      final next = applyRedemption(
        s,
        Redemption(type: RedemptionType.freeDrink, costPts: 200),
      );
      expect(next.points, 50);
      expect(next.lifetimePoints, 250);
      expect(next.stamps, 4);
      expect(next.completedCards, 1);
      expect(next.spinnerTokens, 1);
      expect(next.vouchers, hasLength(1)); // NOT consumed by point redemption
    });

    test('clamps at zero instead of going negative', () {
      final next = applyRedemption(
        _state(points: 30),
        Redemption(type: RedemptionType.freeSnack, costPts: 150),
      );
      expect(next.points, 0);
    });

    test('tier unaffected — derived from lifetime, not spendable balance', () {
      final next = applyRedemption(
        _state(points: 2100, lifetime: 2100),
        Redemption(type: RedemptionType.freeDrink, costPts: 200),
      );
      expect(next.tier, Tier.silver);
    });
  });

  group('creditRedeemedOrder — deduction rides the credit', () {
    test('free drink: 200 pts spent, earn added on discounted spend', () {
      // 15 EGP discounted spend earns 2 pts (15×1/10=1.5 → round half-up 2)
      // but sits below the 50 EGP stamp threshold → no stamp movement.
      final s = creditRedeemedOrder(
        _state(points: 250, lifetime: 250),
        redemption: const Redemption(
            type: RedemptionType.freeDrink, costPts: 200),
        earned: 2,
        subtotalEgp: 15,
      );
      expect(s.points, 52); // 250 − 200 spent + 2 earned
      expect(
        s.lifetimePoints,
        252, // lifetime grows by EARN only — applyRedemption touches points
      ); // only; the redemption cost never spends down lifetime/tier.
    });

    test('null redemption behaves exactly like creditOrder', () {
      final base = _state(points: 30, lifetime: 100, stamps: 9);
      final combined = creditRedeemedOrder(
        base,
        redemption: null,
        earned: 5,
        subtotalEgp: 55, // ≥ 50 threshold → qualifies for a stamp
      );
      final plain = creditOrder(base, earned: 5, subtotalEgp: 55);
      expect(combined.points, plain.points);
      expect(combined.lifetimePoints, plain.lifetimePoints);
      expect(combined.stamps, plain.stamps);
      expect(combined.completedCards, plain.completedCards);
      expect(combined.spinnerTokens, plain.spinnerTokens);
      // Plan 002 unification: both paths now complete the card at the 10th
      // stamp, each stamping its own wall-clock grantedAt on the new voucher
      // — so compare length/type here instead of full list equality.
      expect(combined.vouchers.length, plain.vouchers.length);
      expect(combined.processedOrders, plain.processedOrders);
      // Plan 002 unification: the qualifying visit is the 10th stamp → the
      // card completes and resets to 0 in BOTH transitions; 0 is not an
      // every-3rd-stamp position, so spinner tokens stay put. Voucher shape
      // is compared by type — each call stamps its own wall-clock grantedAt.
      expect(combined.stamps, 0);
      expect(combined.completedCards, 1);
      expect(combined.vouchers.single.type, VoucherType.freeSnack);
      expect(plain.vouchers.single.type, VoucherType.freeSnack);
      expect(combined.spinnerTokens, base.spinnerTokens);
    });

    test('balance floors at 0 when cost exceeds balance', () {
      // applyRedemption clamps before crediting: max(0, 30−150)=0, then +3.
      final s = creditRedeemedOrder(
        _state(points: 30),
        redemption:
            const Redemption(type: RedemptionType.freeSnack, costPts: 150),
        earned: 3,
        subtotalEgp: 60,
      );
      expect(s.points, 3); // floored at 0, then earn applied
      expect(s.lifetimePoints, 3);
    });
  });

  group('drinkLineDiscountEgp', () {
    test('highest-priced drink LINE wins (unit × qty)', () {
      final discount = drinkLineDiscountEgp([
        (categorySlug: 'snacks', lineTotalEgp: 45),
        (categorySlug: 'cold_drinks', lineTotalEgp: 70), // 35×2
        (categorySlug: 'hot_drinks', lineTotalEgp: 40),
      ]);
      expect(discount, 70);
    });

    test('zero when the cart has no drink line', () {
      expect(
        drinkLineDiscountEgp([
          (categorySlug: 'snacks', lineTotalEgp: 30),
          (categorySlug: 'specials', lineTotalEgp: 55),
        ]),
        0,
      );
      expect(drinkLineDiscountEgp(const []), 0);
    });
  });

  group('LoyaltyRulesConfig.fromMap — app_config parsing + fallbacks', () {
    test('parses seeded scalar values (jsonb numbers and strings)', () {
      final c = LoyaltyRulesConfig.fromMap({
        'points_per_10egp': 2,
        'dine_in_multiplier': 1.25,
        'stamp_min_spend': 60,
        'redeem_min_points': 250,
        'reward_topping': '120',
        'reward_snack': '180',
        'reward_drink': '260',
      });
      expect(c.pointsPer10Egp, 2.0);
      expect(c.dineInMultiplier, 1.25);
      expect(c.stampMinSpendEgp, 60);
      expect(c.redeemMinPoints, 250);
      expect(c.rewardToppingPts, 120);
      expect(c.rewardSnackPts, 180);
      expect(c.rewardDrinkPts, 260);
    });

    test('empty/garbage map keeps every seed default', () {
      const fallback = LoyaltyRulesConfig.fallback;
      for (final map in [
        const <String, dynamic>{},
        {'stamp_min_spend': 'not-a-number'},
      ]) {
        final c = LoyaltyRulesConfig.fromMap(map);
        expect(c.pointsPer10Egp, fallback.pointsPer10Egp);
        expect(c.dineInMultiplier, fallback.dineInMultiplier);
        expect(c.stampMinSpendEgp, fallback.stampMinSpendEgp);
        expect(c.redeemMinPoints, fallback.redeemMinPoints);
        expect(c.rewardToppingPts, fallback.rewardToppingPts);
        expect(c.rewardSnackPts, fallback.rewardSnackPts);
        expect(c.rewardDrinkPts, fallback.rewardDrinkPts);
      }
    });

    test('seed constants match migration 0001 app_config seeds', () {
      expect(kPointsPer10Egp, 1.0);
      expect(kDineInMultiplier, 1.1);
      expect(kStampMinSpendEgp, 50);
      expect(kRedeemMinPoints, 200);
      expect(kRewardToppingPts, 100);
      expect(kRewardSnackPts, 150);
      expect(kRewardDrinkPts, 200);
    });
  });
}
