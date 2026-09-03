// Pure Spinner of Luck engine (#008 / FEATURES §5.1 + 0050 thorough) — no state, no IO.
// The wheel shows 7 physical slices (0050) while odds stay governed by weights:
// ٥ نقاط split across two adjacent 15% slices (combined 30%) + rare drinkVoucher 5% when enabled.
import 'dart:math';

import 'package:flutter/material.dart' show IconData, Icons;

/// Prizes tuned rare-on-big-wins (issue #008, 0050): points5 30% · points10 25% ·
/// toppingVoucher 15% (20→15 when drink enabled) · doubleNext 10% · drinkVoucher 5% · nothing 15%.
enum SpinPrize { points5, points10, toppingVoucher, doubleNext, drinkVoucher, nothing }

extension SpinPrizeX on SpinPrize {
  /// Relative probability weight — 0050 thorough: 7-slice wheel, rare drink 5%.
  /// Default seed 30/25/15/10/5/15 =100 (topping 20→15 to keep total 100).
  double get weight => switch (this) {
        SpinPrize.points5 => 30,
        SpinPrize.points10 => 25,
        SpinPrize.toppingVoucher => 15,
        SpinPrize.doubleNext => 10,
        SpinPrize.drinkVoucher => 5,
        SpinPrize.nothing => 15,
      };

  String get labelAr => switch (this) {
        SpinPrize.points5 => '٥ نقاط',
        SpinPrize.points10 => '١٠ نقاط',
        SpinPrize.toppingVoucher => 'توبينج مجاني',
        SpinPrize.doubleNext => 'ضعف الطلب الجاي',
        SpinPrize.drinkVoucher => 'مشروب مجاني',
        SpinPrize.nothing => 'حظ أوفر',
      };

  String get labelEn => switch (this) {
        SpinPrize.points5 => '5 pts',
        SpinPrize.points10 => '10 pts',
        SpinPrize.toppingVoucher => 'Free topping',
        SpinPrize.doubleNext => 'Double next order',
        SpinPrize.drinkVoucher => 'Free drink',
        SpinPrize.nothing => 'Try again',
      };

  IconData get icon => switch (this) {
        SpinPrize.points5 => Icons.stars,
        SpinPrize.points10 => Icons.star,
        SpinPrize.toppingVoucher => Icons.icecream,
        SpinPrize.doubleNext => Icons.bolt,
        SpinPrize.drinkVoucher => Icons.local_cafe,
        SpinPrize.nothing => Icons.refresh,
      };
}

/// Physical slice order — 7 slices (0050 thorough): twin ٥ نقاط (0,1) then one per remaining prize.
const List<SpinPrize> kSpinnerSlices = [
  SpinPrize.points5,
  SpinPrize.points5,
  SpinPrize.points10,
  SpinPrize.toppingVoucher,
  SpinPrize.doubleNext,
  SpinPrize.drinkVoucher,
  SpinPrize.nothing,
];

const int kSpinnerSliceCount = 7;
const double kSpinnerSliceAngleDeg = 360 / kSpinnerSliceCount;

/// Weighted pick over prizes; `r.nextDouble() * totalWeight` walk.
SpinPrize roll(Random r) {
  final total = SpinPrize.values.fold<double>(0, (s, p) => s + p.weight);
  var t = r.nextDouble() * total;
  for (final prize in SpinPrize.values) {
    t -= prize.weight;
    if (t < 0) return prize;
  }
  return SpinPrize.values.last;
}

/// Uniform pick among the physical slices showing [prize] (twin ٥ نقاط).
int sliceIndexFor(SpinPrize prize, Random r) {
  final matches = <int>[
    for (var i = 0; i < kSpinnerSliceCount; i++)
      if (kSpinnerSlices[i] == prize) i,
  ];
  return matches[r.nextInt(matches.length)];
}

/// Absolute final rotation (degrees, clockwise-positive) that parks
/// [sliceIndex]'s center under the fixed top pointer. Slices are laid out
/// clockwise from 12 o'clock at rotation = 0.
double spinTargetRotation({
  required double currentRotation,
  required int sliceIndex,
  required int extraTurns,
}) {
  final desiredMod =
      (-kSpinnerSliceAngleDeg * (sliceIndex + 0.5)) % 360;
  final delta = (desiredMod - currentRotation) % 360;
  return currentRotation + extraTurns * 360 + delta;
}

/// Inverse of [spinTargetRotation]: which physical slice sits under the top
/// pointer at the given absolute rotation.
int sliceUnderPointer(double rotation) {
  final local = (360 - (rotation % 360)) % 360;
  return (local ~/ kSpinnerSliceAngleDeg) % kSpinnerSliceCount;
}

/// Runs [n] seeded rolls and counts outcomes — used by tests to assert the
/// distribution tracks the weights within tolerance.
Map<SpinPrize, int> simulateSpins(int n, Random r) {
  final counts = {for (final p in SpinPrize.values) p: 0};
  for (var i = 0; i < n; i++) {
    final prize = roll(r);
    counts[prize] = counts[prize]! + 1;
  }
  return counts;
}
