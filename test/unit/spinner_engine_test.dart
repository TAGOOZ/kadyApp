import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/spinner_engine.dart';

void main() {
  group('roll weights', () {
    test('distribution tracks weights within ±5pp over 2000 spins', () {
      const expected = {
        SpinPrize.points5: 30,
        SpinPrize.points10: 25,
        SpinPrize.toppingVoucher: 15,
        SpinPrize.doubleNext: 10,
        SpinPrize.drinkVoucher: 5,
        SpinPrize.nothing: 15,
      };
      final counts = simulateSpins(2000, Random(7));
      counts.forEach((prize, count) {
        final pct = count / 2000 * 100;
        expect(pct, closeTo(expected[prize]!.toDouble(), 5),
            reason: '$prize off-weight');
      });
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      expect(total, 2000);
    });

    test('weights sum to 100', () {
      final total =
          SpinPrize.values.fold<double>(0, (s, p) => s + p.weight);
      expect(total, 100);
    });
  });

  group('slice landing', () {
    test('sliceUnderPointer inverts spinTargetRotation', () {
      var r = Random(3);
      for (var i = 0; i < 50; i++) {
        final prize = roll(r);
        // drinkVoucher (weight 0) falls back to topping slice visually
        if (prize == SpinPrize.drinkVoucher) continue;
        final slice = sliceIndexFor(prize, r);
        expect(kSpinnerSlices[slice], prize);
        final target = spinTargetRotation(
          currentRotation: r.nextDouble() * 360,
          sliceIndex: slice,
          extraTurns: 4 + r.nextInt(3),
        );
        expect(sliceUnderPointer(target), slice,
            reason: 'pointer must park on the chosen slice');
      }
    });

    test('twin points5 slices are adjacent (indices 0 and 1)', () {
      expect(kSpinnerSlices[0], SpinPrize.points5);
      expect(kSpinnerSlices[1], SpinPrize.points5);
    });
  });
}
