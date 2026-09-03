// lib/domain/pricing.dart — Candidate 3 deep Pricing module.
//
// Single source of truth for quote(cart) → {subtotal, deliveryFee, total,
// earnedPreview} used by both client preview and server validation.
//
// Hides internally: size deltas, addon prices, flat delivery fee (15 EGP),
// dine-in multiplier (1.1), stamp threshold, rounding. Exposes only the
// narrow `quote()` / unit-total seam.
//
// Seeded catalog note (supabase/migrations/0005_el_kady_menu.sql):
//   The DB seed creates 101 rows where small/large variants are separate
//   MenuItem rows with distinct base prices (e.g. 'قهوة القاضي صغير' 35 EGP
//   vs 'كبير' 50 EGP). The ItemConfig sizeDelta (0 / 10 / 15) is an *additive*
//   delta applied on top of whichever row the customer adds. The current UI
//   (lib/ui/menu/item_detail_sheet.dart) still exposes size choices for every
//   item, so sizeDelta stacks on the row's base price. The pricing trigger
//   (supabase/migrations/0029_fix_pricing_validation.sql) therefore recomputes
//   as `menu_items.price_egp + sizeDelta + addonPrices` for validation — the
//   same additive model the client preview uses — ensuring preview == credited.
//   A future consolidation could store a single base row per drink and apply
//   only deltas, or store per-item addon catalogs in menu_items.config jsonb.
//
// Layer: pure domain (no Riverpod, no Supabase). Cart and orders_repository
// both delegate here, giving one test surface: quote(empty), quote(addon),
// quote(redeemed).
import 'loyalty_rules.dart';
import 'menu_models.dart';

// ---------------------------------------------------------------------------
// Hidden catalog — canonical (ItemConfig duplicates these literals for backwards
// compat; this module is the seam behind which they live).
// ---------------------------------------------------------------------------

/// Size price deltas EGP: 0 small · 1 medium (+10) · 2 large (+15).
/// Matches ItemConfig.sizeDeltasEgp but owned here for the quote seam.
const List<int> kPricingSizeDeltasEgp = [0, 10, 15];

/// Addon price catalog EGP. Mirrors ItemConfig.addonPricesEgp — keep identical.
/// Server trigger (0029) hard-codes the same map in plpgsql.
const Map<String, int> kPricingAddonPricesEgp = {
  'espresso_shot': 15,
  'caramel': 10,
  'whipped_cream': 12,
};

/// Default flat delivery fee EGP (§11.7 citywide, admin-editable via
/// app_config.delivery_fee). Hides the "15" behind FeeTable.
const int kPricingDefaultDeliveryFeeEgp = 15;

/// EGP per point before multipliers (§4).
const int kPricingEgpPerPoint = 10;

// ---------------------------------------------------------------------------
// Low-level encoding: ItemConfig → unitTotal (price + sizeDelta + addons)
// Single source for `items[].unit_total` encoding — already price+deltas
// client-side (lib/data/repos/orders_repository.dart OrderItemPayload).
// ---------------------------------------------------------------------------

/// Canonical unit total for one piece: base price + size delta + addon sum.
/// Throws [ArgumentError] on out-of-range size (corrupted cart JSON) rather
/// than silent clamp — mismatched priced order must fail fast (22023 in SQL).
int pricingUnitTotalFor(MenuItem item, ItemConfig config) {
  if (config.sizeIndex < 0 || config.sizeIndex > 2) {
    throw ArgumentError.value(config.sizeIndex, 'sizeIndex', 'must be 0..2');
  }
  final sizeDelta = kPricingSizeDeltasEgp[config.sizeIndex];
  var addonTotal = 0;
  for (final id in config.addons) {
    addonTotal += kPricingAddonPricesEgp[id] ?? 0;
  }
  return item.priceEgp + sizeDelta + addonTotal;
}

/// Line total before quantity-discount: unitTotal * qty.
int pricingLineTotalFor(MenuItem item, ItemConfig config, int qty) {
  return pricingUnitTotalFor(item, config) * qty;
}

// ---------------------------------------------------------------------------
// Cart-level helpers: subtotal, fee, total.
// ---------------------------------------------------------------------------

/// Flat fee table — delivery pays configured fee, pickup/dine-in pay nothing.
int pricingDeliveryFeeFor({
  required bool isDelivery,
  int configuredFeeEgp = kPricingDefaultDeliveryFeeEgp,
}) {
  return isDelivery ? configuredFeeEgp : 0;
}

int pricingTotalOf({
  required int subtotalEgp,
  required int deliveryFeeEgp,
}) =>
    subtotalEgp + deliveryFeeEgp;

/// Round half-up on the FINAL earned value after multipliers (§4).
/// Duplicates loyalty_rules.roundHalfUp — kept identical; loyalty_rules remains
/// canonical for pure earn, pricing reuses same arithmetic for quote interface.
int pricingRoundHalfUp(double value) {
  final floored = value.floor();
  final fraction = value - floored;
  return floored + (fraction >= 0.5 ? 1 : 0);
}

// ---------------------------------------------------------------------------
// Quote — deep interface hides deltas/fees/multipliers.
// ---------------------------------------------------------------------------

/// Lightweight cart line for the pricing seam — mirrors CartLine (cart_controller)
/// but lives in domain without importing the controller, avoiding a cycle
/// (cart_controller → pricing → cart_controller). Adapters map their own
/// CartLine / OrderItemPayload into this type.
class PricingCartLine {
  const PricingCartLine({
    required this.item,
    required this.config,
    required this.qty,
  });

  final MenuItem item;
  final ItemConfig config;
  final int qty;
}

/// Deep quote result — subtotal (after redemption discount), delivery fee,
/// total, and loyalty earn preview on the same subtotal. Single test surface.
class PricingQuote {
  const PricingQuote({
    required this.subtotalEgp,
    required this.deliveryFeeEgp,
    required this.totalEgp,
    required this.earnedPreview,
    required this.discountEgp,
  });

  final int subtotalEgp;
  final int deliveryFeeEgp;
  final int totalEgp;
  final int earnedPreview;
  final int discountEgp;

  @override
  String toString() =>
      'PricingQuote(subtotal:$subtotalEgp, fee:$deliveryFeeEgp, total:$totalEgp, earned:$earnedPreview, discount:$discountEgp)';
}

/// Discount for a free-drink redemption: zeroes the highest-priced drink line.
/// Delegates to loyalty_rules.drinkLineDiscountEgp so the rule stays single-sourced.
int pricingDiscountFor({
  required List<PricingCartLine> lines,
  required Redemption? redemption,
}) {
  if (redemption == null || redemption.type != RedemptionType.freeDrink) {
    return 0;
  }
  final records = [
    for (final l in lines)
      (
        categorySlug: l.item.categorySlug,
        lineTotalEgp: pricingLineTotalFor(l.item, l.config, l.qty),
      ),
  ];
  return drinkLineDiscountEgp(records);
}

/// One call that owns all pricing math for both client preview and server
/// validation. Callers pass the cart lines, service mode booleans, fee config,
/// loyalty config, and optional redemption — they never compute deltas/fees/earn
/// themselves.
PricingQuote pricingQuote({
  required List<PricingCartLine> lines,
  required bool isDelivery,
  required bool isDineIn,
  int configuredDeliveryFeeEgp = kPricingDefaultDeliveryFeeEgp,
  LoyaltyRulesConfig loyaltyConfig = LoyaltyRulesConfig.fallback,
  Redemption? redemption,
  bool doubleWindow = false,
}) {
  var rawSubtotal = 0;
  for (final l in lines) {
    rawSubtotal += pricingLineTotalFor(l.item, l.config, l.qty);
  }
  final discount = pricingDiscountFor(lines: lines, redemption: redemption);
  final subtotal = rawSubtotal - discount < 0 ? 0 : rawSubtotal - discount;
  final deliveryFee = pricingDeliveryFeeFor(
    isDelivery: isDelivery,
    configuredFeeEgp: configuredDeliveryFeeEgp,
  );
  final total = pricingTotalOf(
    subtotalEgp: subtotal,
    deliveryFeeEgp: deliveryFee,
  );
  final earned = earnedFor(
    subtotalEgp: subtotal,
    dineIn: isDineIn,
    pointsPer10: loyaltyConfig.pointsPer10Egp,
    dineInMultiplier: loyaltyConfig.dineInMultiplier,
    doubleWindow: doubleWindow,
    doubleMaxExtra: loyaltyConfig.doubleMaxExtra,
  );
  return PricingQuote(
    subtotalEgp: subtotal,
    deliveryFeeEgp: deliveryFee,
    totalEgp: total,
    earnedPreview: earned,
    discountEgp: discount,
  );
}

/// Convenience: quote from a raw subtotal (e.g. orders_repository existing int)
/// still applying fee/total/earn consistently. Prefer [pricingQuote] when lines
/// are available so redemption discount is accurate.
PricingQuote pricingQuoteFromSubtotal({
  required int rawSubtotalEgp,
  required bool isDelivery,
  required bool isDineIn,
  int configuredDeliveryFeeEgp = kPricingDefaultDeliveryFeeEgp,
  LoyaltyRulesConfig loyaltyConfig = LoyaltyRulesConfig.fallback,
  int discountEgp = 0,
  bool doubleWindow = false,
}) {
  final subtotal = rawSubtotalEgp - discountEgp < 0 ? 0 : rawSubtotalEgp - discountEgp;
  final deliveryFee = pricingDeliveryFeeFor(
    isDelivery: isDelivery,
    configuredFeeEgp: configuredDeliveryFeeEgp,
  );
  final total = pricingTotalOf(subtotalEgp: subtotal, deliveryFeeEgp: deliveryFee);
  final earned = earnedFor(
    subtotalEgp: subtotal,
    dineIn: isDineIn,
    pointsPer10: loyaltyConfig.pointsPer10Egp,
    dineInMultiplier: loyaltyConfig.dineInMultiplier,
    doubleWindow: doubleWindow,
    doubleMaxExtra: loyaltyConfig.doubleMaxExtra,
  );
  return PricingQuote(
    subtotalEgp: subtotal,
    deliveryFeeEgp: deliveryFee,
    totalEgp: total,
    earnedPreview: earned,
    discountEgp: discountEgp,
  );
}
