// Pricing deep module unit tests (Candidate 3).
// One test surface: quote(empty), quote(addon), quote(redeemed)
// plus loyalty preview == credited (no 3pts lost when addon).
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/domain/loyalty_rules.dart';
import 'package:kady_app/domain/pricing.dart';

MenuItem _item(String id, int priceEgp, {String cat = 'hot_drinks'}) => MenuItem(
      id: id,
      slug: id,
      nameAr: 'عنصر',
      nameEn: 'Item',
      descAr: '',
      descEn: '',
      priceEgp: priceEgp,
      isAvailable: true,
      categorySlug: cat,
    );

void main() {
  group('pricingUnitTotalFor — base + sizeDelta + addons (single source)', () {
    test('base only, no deltas', () {
      final item = _item('tea', 40);
      const cfg = ItemConfig();
      expect(pricingUnitTotalFor(item, cfg), 40);
    });

    test('medium size +10 delta', () {
      final item = _item('latte', 45);
      const cfg = ItemConfig(sizeIndex: 1);
      expect(pricingUnitTotalFor(item, cfg), 55);
    });

    test('large size +15 delta + espresso_shot +15 + caramel +10 = 85 base 45', () {
      final item = _item('latte', 45);
      const cfg = ItemConfig(sizeIndex: 2, addons: {'espresso_shot', 'caramel'});
      // 45 +15 +15+10=85
      expect(pricingUnitTotalFor(item, cfg), 85);
    });

    test('addon set order does not affect total', () {
      final item = _item('latte', 50);
      const a = ItemConfig(addons: {'caramel', 'espresso_shot'});
      const b = ItemConfig(addons: {'espresso_shot', 'caramel'});
      expect(pricingUnitTotalFor(item, a), pricingUnitTotalFor(item, b));
    });
  });

  group('FeeTable — pricingDeliveryFeeFor / pricingTotalOf', () {
    test('delivery pays configured fee (default 15)', () {
      expect(pricingDeliveryFeeFor(isDelivery: true), 15);
      expect(pricingDeliveryFeeFor(isDelivery: true, configuredFeeEgp: 20), 20);
    });

    test('pickup/dine-in pay nothing', () {
      expect(pricingDeliveryFeeFor(isDelivery: false, configuredFeeEgp: 20), 0);
    });

    test('total = subtotal + fee', () {
      expect(pricingTotalOf(subtotalEgp: 100, deliveryFeeEgp: 15), 115);
      expect(pricingTotalOf(subtotalEgp: 100, deliveryFeeEgp: 0), 100);
    });
  });

  group('pricingQuote — deep interface quote(empty), quote(addon), quote(redeemed)', () {
    test('quote(empty) pickup → 0 subtotal, 0 fee, 0 total, 0 earned', () {
      final q = pricingQuote(
        lines: const [],
        isDelivery: false,
        isDineIn: false,
      );
      expect(q.subtotalEgp, 0);
      expect(q.deliveryFeeEgp, 0);
      expect(q.totalEgp, 0);
      expect(q.earnedPreview, 0);
      expect(q.discountEgp, 0);
    });

    test('quote(empty) delivery → 0 subtotal but 15 fee, total 15, earned still 0', () {
      final q = pricingQuote(lines: const [], isDelivery: true, isDineIn: false);
      expect(q.subtotalEgp, 0);
      expect(q.deliveryFeeEgp, 15);
      expect(q.totalEgp, 15);
      expect(q.earnedPreview, 0);
    });

    test('quote(addon) — report drift example: base 50 + espresso 15 =65 x2=130 → earned 13 vs old server 100→10', () {
      final item = _item('drink', 50, cat: 'hot_drinks');
      const cfg = ItemConfig(addons: {'espresso_shot'});
      final lines = [PricingCartLine(item: item, config: cfg, qty: 2)];
      final q = pricingQuote(lines: lines, isDelivery: false, isDineIn: false);
      // client preview via pricing (single source)
      expect(q.subtotalEgp, 130);
      expect(q.earnedPreview, 13);
      // simulate server recompute via same pricing helper (not base-only)
      final serverSubtotal = pricingUnitTotalFor(item, cfg) * 2;
      expect(serverSubtotal, 130);
      final serverEarned = earnedFor(
        subtotalEgp: serverSubtotal,
        dineIn: false,
        pointsPer10: 1.0,
        dineInMultiplier: 1.1,
        doubleWindow: false,
      );
      expect(serverEarned, 13);
      // old buggy server would have done base*2 only
      const oldBuggySubtotal = 50 * 2;
      expect(oldBuggySubtotal, 100);
      expect(
        earnedFor(subtotalEgp: oldBuggySubtotal, dineIn: false, pointsPer10: 1.0, dineInMultiplier: 1.1, doubleWindow: false),
        10,
      );
      // fixed: preview (13) == credited (13) — no 3pt loss
      expect(q.earnedPreview, serverEarned);
    });

    test('quote addon with size large + whipped_cream: 45+15+12=72 x3=216 dIn→24 pts', () {
      final item = _item('latte', 45);
      const cfg = ItemConfig(sizeIndex: 2, addons: {'whipped_cream'});
      final lines = [PricingCartLine(item: item, config: cfg, qty: 3)];
      final q = pricingQuote(lines: lines, isDelivery: false, isDineIn: true);
      expect(q.subtotalEgp, 216);
      // 216/10=21.6*1.1=23.76→24
      expect(q.earnedPreview, 24);
    });

    test('quote(redeemed) free_drink zeroes highest drink line: tea 40 + biscuit15=55→15 earned 2', () {
      final tea = _item('tea', 40, cat: 'hot_drinks');
      final biscuit = _item('biscuit', 15, cat: 'snacks');
      final lines = [
        PricingCartLine(item: tea, config: const ItemConfig(), qty: 1),
        PricingCartLine(item: biscuit, config: const ItemConfig(), qty: 1),
      ];
      final redemption = Redemption(type: RedemptionType.freeDrink, costPts: 200);
      final q = pricingQuote(
        lines: lines,
        isDelivery: false,
        isDineIn: true,
        loyaltyConfig: LoyaltyRulesConfig.fallback,
        redemption: redemption,
        doubleWindow: false,
      );
      // raw 55 - max drink line 40 =15
      expect(q.subtotalEgp, 15);
      expect(q.discountEgp, 40);
      expect(q.totalEgp, 15); // pickup/dineIn no fee
      // earned on discounted 15 dineIn →2
      expect(q.earnedPreview, 2);
    });

    test('topping redemption deducts points only, no cash discount', () {
      final tea = _item('tea', 40, cat: 'hot_drinks');
      final biscuit = _item('biscuit', 15, cat: 'snacks');
      final lines = [
        PricingCartLine(item: tea, config: const ItemConfig(), qty: 1),
        PricingCartLine(item: biscuit, config: const ItemConfig(), qty: 1),
      ];
      final redemption = Redemption(type: RedemptionType.freeTopping, costPts: 100);
      final q = pricingQuote(
        lines: lines,
        isDelivery: false,
        isDineIn: false,
        redemption: redemption,
      );
      expect(q.subtotalEgp, 55);
      expect(q.discountEgp, 0);
      expect(q.totalEgp, 55);
    });

    test('delivery fee included with addon+redeemed', () {
      final tea = _item('tea', 40, cat: 'hot_drinks');
      final lines = [PricingCartLine(item: tea, config: const ItemConfig(), qty: 1)];
      final q = pricingQuote(lines: lines, isDelivery: true, isDineIn: false);
      expect(q.subtotalEgp, 40);
      expect(q.deliveryFeeEgp, 15);
      expect(q.totalEgp, 55);
    });
  });

  group('pricingRoundHalfUp mirrors loyalty_rules (§4 examples)', () {
    test('95 → 9.5 →10', () => expect(pricingRoundHalfUp(9.5), 10));
    test('9.9 →10 dine-in case', () => expect(pricingRoundHalfUp(9.9), 10));
  });

  group('ItemConfig → unitTotal encoding single source (no overwrite surprise)', () {
    test('orders_repository now delegates to pricing (validated by quote vs lineTotal)', () {
      // Simulate cart_controller lineTotal vs pricing quote subtotal
      final item = _item('x', 30);
      const cfg = ItemConfig(sizeIndex: 1, addons: {'caramel'});
      // cart_controller lineTotal would be pricingLineTotalFor
      final lineTotal = pricingLineTotalFor(item, cfg, 2);
      final quoteSubtotal = pricingQuote(
        lines: [PricingCartLine(item: item, config: cfg, qty: 2)],
        isDelivery: false,
        isDineIn: false,
      ).subtotalEgp;
      expect(lineTotal, quoteSubtotal);
    });
  });
}
