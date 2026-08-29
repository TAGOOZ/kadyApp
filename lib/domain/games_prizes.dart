// Shared weighted prize table for the game slices (#008/#009 / FEATURES §5) —
// pure, no state, no IO. Scratch & Win rolls it directly; 3-Card Match maps
// its round outcomes onto the same vocabulary (twoMatch → pts5,
// threeMatch → drinkVoucher) so both games credit identically.
import 'dart:math';

import 'package:flutter/material.dart' show IconData, Icons;

import 'loyalty_controller.dart';

/// Prizes tuned rare-on-big-wins: pts5 30% · pts10 25% · toppingVoucher 20% ·
/// drinkVoucher 10% · nothing 15% (weights sum to 100).
enum GamePrize { pts5, pts10, toppingVoucher, drinkVoucher, nothing }

extension GamePrizeX on GamePrize {
  /// Relative probability weight (sums to 100 across [GamePrize.values]).
  double get weight => switch (this) {
        GamePrize.pts5 => 30,
        GamePrize.pts10 => 25,
        GamePrize.toppingVoucher => 20,
        GamePrize.drinkVoucher => 10,
        GamePrize.nothing => 15,
      };

  String get labelAr => switch (this) {
        GamePrize.pts5 => '٥ نقاط',
        GamePrize.pts10 => '١٠ نقاط',
        GamePrize.toppingVoucher => 'توبينج مجاني',
        GamePrize.drinkVoucher => 'مشروب مجاني',
        GamePrize.nothing => 'حظ أوفر',
      };

  IconData get icon => switch (this) {
        GamePrize.pts5 => Icons.stars,
        GamePrize.pts10 => Icons.star,
        GamePrize.toppingVoucher => Icons.icecream,
        GamePrize.drinkVoucher => Icons.local_cafe,
        GamePrize.nothing => Icons.refresh,
      };

  bool get isVoucher =>
      this == GamePrize.toppingVoucher || this == GamePrize.drinkVoucher;
}

/// Weighted pick over prizes; `r.nextDouble() * totalWeight` walk.
GamePrize roll(Random r) {
  final total = GamePrize.values.fold<double>(0, (s, p) => s + p.weight);
  var t = r.nextDouble() * total;
  for (final prize in GamePrize.values) {
    t -= prize.weight;
    if (t < 0) return prize;
  }
  return GamePrize.values.last;
}

/// Runs [n] seeded rolls and counts outcomes — used by tests to assert the
/// distribution tracks the weights within tolerance.
Map<GamePrize, int> simulate(int n, Random r) {
  final counts = {for (final p in GamePrize.values) p: 0};
  for (var i = 0; i < n; i++) {
    final prize = roll(r);
    counts[prize] = counts[prize]! + 1;
  }
  return counts;
}

/// Applies a game outcome via [controller] through the shared loyalty seam —
/// nothing is granted for [GamePrize.nothing] (token already consumed).
Future<void> creditGamePrize(LoyaltyController controller, GamePrize prize) =>
    switch (prize) {
      GamePrize.pts5 => controller.grantPoints(5),
      GamePrize.pts10 => controller.grantPoints(10),
      GamePrize.toppingVoucher =>
        controller.grantVoucher(VoucherType.freeTopping),
      GamePrize.drinkVoucher => controller.grantVoucher(VoucherType.freeDrink),
      GamePrize.nothing => Future.value(),
    };
