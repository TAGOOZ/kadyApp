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
    test('9→10 fills the card WITHOUT completing it', () {
      final s = creditOrder(_state(stamps: 9), earned: 5, subtotalEgp: 80);
      expect(s.stamps, 10);
      expect(s.completedCards, 0);
      expect(s.vouchers, isEmpty);
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
      // Corrupted row with stamps=19 → 20 > 10 → wrap must show 10, never 0.
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
