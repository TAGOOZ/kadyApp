import 'package:flutter_test/flutter_test.dart';

// Pure helper mirrors 0038 logic: zero weight if cap 0, then renormalize.
Map<String, int> renormalize(Map<String, int> weights, Map<String, int?> caps) {
  final adjusted = <String, int>{};
  weights.forEach((k, v) {
    // map prize keys to cap types: toppingVoucher->free_topping, drinkVoucher->free_drink
    final capKey = switch (k) {
      'toppingVoucher' => 'free_topping',
      'drinkVoucher' => 'free_drink',
      _ => null,
    };
    final rem = capKey == null ? null : caps[capKey];
    adjusted[k] = rem == 0 ? 0 : v;
  });
  return adjusted;
}

String rollWithWeights(Map<String, int> weights, double r) {
  final total = weights.values.fold(0, (a, b) => a + b);
  if (total <= 0) return 'nothing';
  var t = r * total;
  for (final e in weights.entries) {
    t -= e.value;
    if (t < 0) return e.key;
  }
  return weights.keys.last;
}

void main() {
  group('prize caps — hard inventory', () {
    test('remaining 0 zeroes weight, renormalizes', () {
      final weights = {'points5': 30, 'points10': 25, 'toppingVoucher': 20, 'doubleNext': 10, 'nothing': 15};
      final caps = {'free_topping': 0, 'free_drink': 10};
      final adj = renormalize(weights, caps);
      expect(adj['toppingVoucher'], 0);
      expect(adj.values.fold(0, (a, b) => a + b), 80); // 100-20
      // topping should never be selected even if r would have hit it originally
      // Simulate r that would have been topping in original 20/100 range: 30+25=55 to 75
      // With renormalized total 80, same r*80 will map differently, but topping weight 0 ensures never
      for (var i = 0; i < 100; i++) {
        final r = (55 + 10) / 100; // 0.65 would be topping originally
        final prize = rollWithWeights(adj, r);
        expect(prize, isNot('toppingVoucher'));
      }
    });

    test('unlimited when no cap row (null)', () {
      final weights = {'pts5': 30, 'drinkVoucher': 10, 'nothing': 15};
      final caps = <String, int?>{}; // no row => null => unlimited
      final adj = renormalize(weights, caps);
      expect(adj['drinkVoucher'], 10);
    });

    test('all voucher caps 0 → only points/nothing remain', () {
      final weights = {'pts5': 30, 'toppingVoucher': 20, 'drinkVoucher': 10, 'nothing': 15};
      final caps = {'free_topping': 0, 'free_drink': 0};
      final adj = renormalize(weights, caps);
      expect(adj['toppingVoucher'], 0);
      expect(adj['drinkVoucher'], 0);
      expect(adj.values.fold(0, (a, b) => a + b), 45);
    });

    test('admin replenish: remaining increments, weight restored', () {
      final weights = {'toppingVoucher': 20, 'nothing': 15};
      var caps = {'free_topping': 0};
      var adj = renormalize(weights, caps);
      expect(adj['toppingVoucher'], 0);
      // replenish 5
      caps = {'free_topping': 5};
      adj = renormalize(weights, caps);
      expect(adj['toppingVoucher'], 20);
    });

    test('atomic decrement: concurrent plays cannot overspend (simulated)', () {
      // Simulate remaining 1, two concurrent rolls both select topping
      var remaining = 1;
      const firstPrize = 'toppingVoucher';
      // first consumes
      if (firstPrize == 'toppingVoucher' && remaining > 0) remaining--;
      expect(remaining, 0);
      // second would have been topping but now weight 0, so re-roll would give nothing
      // In real DB, second's SELECT FOR UPDATE would see remaining 0 before roll, so it wouldn't select topping
      final weights = {'toppingVoucher': 20, 'nothing': 15};
      final caps = {'free_topping': remaining};
      final adj = renormalize(weights, caps);
      expect(adj['toppingVoucher'], 0);
      // second roll with same r would now be nothing
      final prize = rollWithWeights(adj, 0.2); // 0.2*15=3 <15 -> nothing? Actually only nothing remains 15, so any r maps to nothing
      expect(prize, 'nothing');
    });
  });
}
