// Pure loyalty rule functions (issue #007 / FEATURES §4). No Riverpod, no
// Supabase, no clocks beyond an injected-free voucher timestamp — everything
// here is exhaustively unit-testable. The controller (`loyalty_controller.dart`)
// loads config and persists; these functions decide what a credit/redemption
// MEANS. Config values mirror the `app_config` seeds in
// `supabase/migrations/0001_init.sql` and fall back to those constants offline.
import 'dart:math' as math;

import '../data/repos/orders_repository.dart';
import 'loyalty_controller.dart';

// ---------------------------------------------------------------------------
// Config — seed constants (offline fallbacks) + parse from app_config rows
// ---------------------------------------------------------------------------

/// 1 pt / 10 EGP (`app_config.points_per_10egp`).
const double kPointsPer10Egp = 1.0;

/// Dine-in bonus multiplier (`app_config.dine_in_multiplier`).
const double kDineInMultiplier = 1.1;

/// Minimum spend for a qualifying visit / stamp (`app_config.stamp_min_spend`).
const int kStampMinSpendEgp = 50;

/// Global redemption floor (`app_config.redeem_min_points`).
const int kRedeemMinPoints = 200;

/// Catalog v1 costs (§11.9): topping 100 · snack 150 · drink 200 pts.
const int kRewardToppingPts = 100;
const int kRewardSnackPts = 150;
const int kRewardDrinkPts = 200;

/// Immutable snapshot of the admin-editable loyalty parameters.
class LoyaltyRulesConfig {
  const LoyaltyRulesConfig({
    this.pointsPer10Egp = kPointsPer10Egp,
    this.dineInMultiplier = kDineInMultiplier,
    this.stampMinSpendEgp = kStampMinSpendEgp,
    this.redeemMinPoints = kRedeemMinPoints,
    this.rewardToppingPts = kRewardToppingPts,
    this.rewardSnackPts = kRewardSnackPts,
    this.rewardDrinkPts = kRewardDrinkPts,
  });

  /// Seed values from migration 0001 — used whenever `app_config` is
  /// unreachable (standard offline policy).
  static const LoyaltyRulesConfig fallback = LoyaltyRulesConfig();

  final double pointsPer10Egp;
  final double dineInMultiplier;
  final int stampMinSpendEgp;
  final int redeemMinPoints;
  final int rewardToppingPts;
  final int rewardSnackPts;
  final int rewardDrinkPts;

  /// Parses the flat `{key: scalar}` map produced by [loadConfig] in the
  /// controller. Unknown/missing keys keep their seed defaults.
  factory LoyaltyRulesConfig.fromMap(Map<String, dynamic> map) {
    double numAsDouble(String key, double fallback) {
      final v = map[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    int numAsInt(String key, int fallback) {
      final v = map[key];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return LoyaltyRulesConfig(
      pointsPer10Egp:
          numAsDouble('points_per_10egp', LoyaltyRulesConfig.fallback.pointsPer10Egp),
      dineInMultiplier:
          numAsDouble('dine_in_multiplier', LoyaltyRulesConfig.fallback.dineInMultiplier),
      stampMinSpendEgp:
          numAsInt('stamp_min_spend', LoyaltyRulesConfig.fallback.stampMinSpendEgp),
      redeemMinPoints:
          numAsInt('redeem_min_points', LoyaltyRulesConfig.fallback.redeemMinPoints),
      rewardToppingPts:
          numAsInt('reward_topping', LoyaltyRulesConfig.fallback.rewardToppingPts),
      rewardSnackPts: numAsInt('reward_snack', LoyaltyRulesConfig.fallback.rewardSnackPts),
      rewardDrinkPts: numAsInt('reward_drink', LoyaltyRulesConfig.fallback.rewardDrinkPts),
    );
  }
}

// ---------------------------------------------------------------------------
// Earn
// ---------------------------------------------------------------------------

/// Points earned for one order (§4): base `1 pt / pointsPer10·10 EGP`,
/// dine-in multiplier, campaign ×2 window — rounding half-up applied ONCE to
/// the final value: 90 pickup → 9 · 90 dine-in → 9×1.1=9.9 → 10 · 95 → 9.5 →
/// 10 · 90 pickup during a double window → 18.
int earnedFor({
  required int subtotalEgp,
  required bool dineIn,
  required double pointsPer10,
  required double dineInMultiplier,
  required bool doubleWindow,
}) {
  final base = subtotalEgp * pointsPer10 / 10;
  final scaled =
      base * (dineIn ? dineInMultiplier : 1) * (doubleWindow ? 2 : 1);
  return roundHalfUp(scaled);
}

// ---------------------------------------------------------------------------
// Credit
// ---------------------------------------------------------------------------

/// Applies one processed order to the state: points + lifetime go up by
/// [earned]; when the subtotal meets [stampMinSpendEgp] the visit qualifies
/// and fills one stamp slot. Every 3rd stamp grants a Spinner Token (§5).
/// Overflowing a full card (10 slots) completes it — completedCards+1 and a
/// free-snack Voucher — and the overflow visit opens the next card at its
/// wrapped position (`newStamps % 10`, never 0 mid-card → shown as 10).
LoyaltyState creditOrder(
  LoyaltyState s, {
  required int earned,
  required int subtotalEgp,
  int stampMinSpendEgp = kStampMinSpendEgp,
}) {
  var stamps = s.stamps;
  var completedCards = s.completedCards;
  var spinnerTokens = s.spinnerTokens;
  var vouchers = s.vouchers;

  if (subtotalEgp >= stampMinSpendEgp) {
    final newStamps = stamps + 1;
    if (newStamps > 10) {
      completedCards += 1;
      vouchers = [
        ...vouchers,
        Voucher(
          type: VoucherType.freeSnack,
          grantedAt: DateTime.now().toUtc(),
        ),
      ];
      stamps = newStamps % 10 == 0 ? 10 : newStamps % 10;
    } else {
      stamps = newStamps;
    }
    if (stamps % 3 == 0) spinnerTokens += 1;
  }

  return s.copyWith(
    points: s.points + earned,
    lifetimePoints: s.lifetimePoints + earned,
    stamps: stamps,
    completedCards: completedCards,
    spinnerTokens: spinnerTokens,
    vouchers: vouchers,
  );
}

/// True when [orderId] is already in the state's processed guard list —
/// mirrors the `loyalty_state.processed_orders` jsonb check server-side so
/// local-only (guest) sessions get the same idempotency guarantee.
bool alreadyProcessed(LoyaltyState s, String orderId) =>
    s.processedOrders.contains(orderId);

/// Appends [orderId] to the processed guard list, keeping the newest 100 so
/// the jsonb column cannot grow without bound.
LoyaltyState markProcessed(LoyaltyState s, String orderId) {
  final next = [...s.processedOrders, orderId];
  return s.copyWith(
    processedOrders: next.length > 100 ? next.sublist(next.length - 100) : next,
  );
}

// ---------------------------------------------------------------------------
// Redemption
// ---------------------------------------------------------------------------

enum RedemptionType { freeDrink, freeTopping, freeSnack }

extension RedemptionTypeX on RedemptionType {
  /// Wire vocabulary shared with `VoucherType.key` (notes-prefix encoding:
  /// `[REDEEMED:{type}:{cost}]` inside the order's `notes` text field).
  String get key => switch (this) {
        RedemptionType.freeDrink => 'free_drink',
        RedemptionType.freeTopping => 'free_topping',
        RedemptionType.freeSnack => 'free_snack',
      };
}

/// One concrete checkout redemption: spend [costPts] Points, get [type].
class Redemption {
  const Redemption({required this.type, required this.costPts});

  final RedemptionType type;
  final int costPts;
}

/// Drink category slugs seeded in migration 0001 (`hot_drinks`, `cold_drinks`).
bool isDrinkCategorySlug(String slug) =>
    slug == 'hot_drinks' || slug == 'cold_drinks';

/// The single redemption surfaced at checkout, or null when nothing applies:
///
/// - free_drink: needs ≥ max(redeemMinPoints, rewardDrinkPts) AND a drink line
///   in the cart (hot/cold drinks); zeroes the highest-priced drink line.
/// - free_topping: ≥ rewardToppingPts, also served on a drink → needs a line.
/// - free_snack: ≥ rewardSnackPts, no cart requirement.
///
/// With a drink line present the drink wins (the flagship §11.9 redemption —
/// "استخدم ٢٠٠ نقطة → مشروب مجاني"); otherwise the cheapest affordable of
/// topping/snack applies.
Redemption? redeemable(
  LoyaltyState s, {
  required bool hasDrinkLine,
  LoyaltyRulesConfig config = LoyaltyRulesConfig.fallback,
}) {
  final drinkFloor =
      math.max(config.redeemMinPoints, config.rewardDrinkPts);
  if (hasDrinkLine && s.points >= drinkFloor) {
    return Redemption(type: RedemptionType.freeDrink, costPts: drinkFloor);
  }
  if (hasDrinkLine && s.points >= config.rewardToppingPts) {
    return Redemption(
      type: RedemptionType.freeTopping,
      costPts: config.rewardToppingPts,
    );
  }
  if (s.points >= config.rewardSnackPts) {
    return Redemption(
      type: RedemptionType.freeSnack,
      costPts: config.rewardSnackPts,
    );
  }
  return null;
}

/// Spends the Points for [r]. Vouchers are NOT touched — redemption pays with
/// Points directly; Vouchers remain granted rewards awaiting staff use.
LoyaltyState applyRedemption(LoyaltyState s, Redemption r) {
  return s.copyWith(points: math.max(0, s.points - r.costPts));
}

/// Highest-priced drink line total (unit × qty) — the EGP amount zeroed by a
/// free-drink redemption. Returns 0 when the cart has no drink line.
int drinkLineDiscountEgp(List<({String categorySlug, int lineTotalEgp})> lines) {
  var best = 0;
  for (final line in lines) {
    if (!isDrinkCategorySlug(line.categorySlug)) continue;
    if (line.lineTotalEgp > best) best = line.lineTotalEgp;
  }
  return best;
}

/// Full post-checkout transition for ONE processed order that may carry a
/// checkout redemption: spends [redemption]'s Points first, then credits
/// [earned] against the discounted spend, marks nothing processed (that stays
/// the controller's [markProcessed] call so the idempotency guard keeps its
/// shape). Pure — used by LoyaltyController.creditProcessedOrder so deduction
/// and earn land in a single guarded state transition (and therefore a single
/// persist). Lifetime Points grow by [earned] only — redemption cost never
/// touches them.
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
