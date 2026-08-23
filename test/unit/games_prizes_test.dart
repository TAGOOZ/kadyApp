import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/games_prizes.dart';

void main() {
  group('roll weights', () {
    test('weights sum to 100', () {
      final total = GamePrize.values.fold<double>(0, (s, p) => s + p.weight);
      expect(total, 100);
    });

    test('distribution tracks weights within ±5pp over 2000 seeded rolls',
        () {
      const expected = {
        GamePrize.pts5: 30,
        GamePrize.pts10: 25,
        GamePrize.toppingVoucher: 20,
        GamePrize.drinkVoucher: 10,
        GamePrize.nothing: 15,
      };
      final counts = simulate(2000, Random(7));
      counts.forEach((prize, count) {
        final pct = count / 2000 * 100;
        expect(pct, closeTo(expected[prize]!.toDouble(), 5),
            reason: '$prize off-weight');
      });
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      expect(total, 2000);
    });
  });

  group('credit mapping', () {
    test('voucher prizes map to freeTopping/freeDrink vocabulary', () {
      expect(GamePrize.toppingVoucher.isVoucher, isTrue);
      expect(GamePrize.drinkVoucher.isVoucher, isTrue);
      expect(GamePrize.pts5.isVoucher, isFalse);
      expect(GamePrize.nothing.isVoucher, isFalse);
    });
  });
}
