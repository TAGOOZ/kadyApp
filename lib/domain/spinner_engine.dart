// Pure Spinner of Luck engine (#008 / FEATURES §5.1) — no state, no IO.
// The wheel shows 6 physical slices while odds stay governed by the per-prize
// weights: the ٥ نقاط prize is split across two ADJACENT slices of weight 15
// each (combined 30%). Result is always pre-computed, then animated to.
import 'dart:math';

import 'package:flutter/material.dart' show IconData, Icons;

/// Prizes tuned rare-on-big-wins (issue #008): points5 30% · points10 25% ·
/// toppingVoucher 20% · doubleNext 10% · nothing 15%.
enum SpinPrize { points5, points10, toppingVoucher, doubleNext, nothing }

extension SpinPrizeX on SpinPrize {
  /// Relative probability weight (sums to 100 across [SpinPrize.values]).
  double get weight => switch (this) {
        SpinPrize.points5 => 30,
        SpinPrize.points10 => 25,
        SpinPrize.toppingVoucher => 20,
        SpinPrize.doubleNext => 10,
        SpinPrize.nothing => 15,
      };

  String get labelAr => switch (this) {
        SpinPrize.points5 => '٥ نقاط',
        SpinPrize.points10 => '١٠ نقاط',
        SpinPrize.toppingVoucher => 'توبينج مجاني',
        SpinPrize.doubleNext => 'ضعف الطلب الجاي',
        SpinPrize.nothing => 'حظ أوفر',
      };

  String get labelEn => switch (this) {
        SpinPrize.points5 => '5 pts',
        SpinPrize.points10 => '10 pts',
        SpinPrize.toppingVoucher => 'Free topping',
        SpinPrize.doubleNext => 'Double next order',
        SpinPrize.nothing => 'Try again',
      };

  IconData get icon => switch (this) {
        SpinPrize.points5 => Icons.stars,
        SpinPrize.points10 => Icons.star,
        SpinPrize.toppingVoucher => Icons.icecream,
        SpinPrize.doubleNext => Icons.bolt,
        SpinPrize.nothing => Icons.refresh,
      };
}

/// Physical slice order around the wheel — two adjacent ٥ نقاط slices
/// (indices 0 and 1, weight 15 each), then one slice per remaining prize.
const List<SpinPrize> kSpinnerSlices = [
  SpinPrize.points5,
  SpinPrize.points5,
  SpinPrize.points10,
  SpinPrize.toppingVoucher,
  SpinPrize.doubleNext,
  SpinPrize.nothing,
];

const int kSpinnerSliceCount = 6;
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

/// Uniform pick among the physical slices showing [prize] (the twin ٥ نقاط
/// slices make either landing visually correct).
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
