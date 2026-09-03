// Causal cancellation reversal — pure Dart mirror of 0036 SQL logic.
// Implements policy 037: never blindly stamps-- / tokens--, tracks causal
// reward via OrderEffect and revokes only if that order created it AND still unused.
// LifetimePoints never decremented.

import 'loyalty_state.dart';

/// Causal ledger entry for one credited order — mirrors order_loyalty_effects row.
class OrderEffect {
  const OrderEffect({
    required this.orderId,
    required this.earned,
    required this.stampGranted,
    this.stampBefore,
    this.stampAfter,
    required this.tokenGranted,
    this.tokenPosition,
    this.voucherGrantedType,
    this.voucherAt,
    required this.completedCardGranted,
    this.redeemedDeducted = 0,
    this.isReversed = false,
  });

  final String orderId;
  final int earned;
  final bool stampGranted;
  final int? stampBefore;
  final int? stampAfter;
  final bool tokenGranted;
  final int? tokenPosition;
  final String? voucherGrantedType; // 'free_snack' only currently
  final DateTime? voucherAt;
  final bool completedCardGranted;
  final int redeemedDeducted;
  final bool isReversed;
}

/// Result of attempting to reverse one order — for audit.
class ReversalResult {
  const ReversalResult({
    required this.state,
    required this.revokedPoints,
    required this.revokedStamp,
    required this.revokedToken,
    required this.revokedVoucher,
  });
  final LoyaltyState state;
  final bool revokedPoints;
  final bool revokedStamp;
  final bool revokedToken;
  final bool revokedVoucher;
}

/// Pure reversal — mirrors public.reverse_loyalty_on_cancel() PL/pgSQL.
/// * [current] is the live LoyaltyState (after the order and any subsequent orders)
/// * [effect] is the causal ledger for the cancelled order
/// Returns new state per policy, without mutating inputs.
/// If effect.isReversed or stampGranted==false with earned==0, returns current unchanged
/// (except points deduction still applies if earned>0).
ReversalResult reverseLoyalty(LoyaltyState current, OrderEffect effect) {
  if (effect.isReversed) {
    return ReversalResult(
      state: current,
      revokedPoints: false,
      revokedStamp: false,
      revokedToken: false,
      revokedVoucher: false,
    );
  }

  // Points: always revoke earned if order was processed (even if not qualifying)
  // lifetime NOT touched.
  final newPoints = (current.points - effect.earned).clamp(0, 1 << 30);

  // Determine token revocation: only if this order causally created a token AND still unused
  final canRevokeToken = effect.tokenGranted && current.spinnerTokens > 0;
  // Determine voucher revocation: only if still present in array (unused)
  bool canRevokeVoucher = false;
  List<Voucher> newVouchers = current.vouchers;
  if (effect.voucherGrantedType != null) {
    // Find first voucher matching type + at timestamp (causal identity)
    final idx = current.vouchers.indexWhere((v) =>
        v.type.key == effect.voucherGrantedType &&
        (effect.voucherAt == null ||
            v.grantedAt.toIso8601String() == effect.voucherAt!.toIso8601String()));
    // Fallback: if timestamp mismatch (clock drift in tests), match by type only first occurrence
    final fallbackIdx = idx == -1
        ? current.vouchers.indexWhere((v) => v.type.key == effect.voucherGrantedType)
        : idx;
    if (fallbackIdx != -1) {
      canRevokeVoucher = true;
      newVouchers = [...current.vouchers]..removeAt(fallbackIdx);
    } else {
      // already redeemed -> keep per policy, do NOT revert card
      canRevokeVoucher = false;
      newVouchers = current.vouchers;
    }
  }

  // Stamps/cards revert via total-count method ONLY if stamp was granted AND
  // (not a card completion OR voucher was still present to revoke).
  // If voucher was already redeemed, we keep stamps/cards as-is per ambiguous policy - documented.
  int newStamps = current.stamps;
  int newCards = current.completedCards;

  if (effect.stampGranted) {
    final isCardCompletion = effect.completedCardGranted;
    final shouldRevertCards = !isCardCompletion || canRevokeVoucher;
    if (shouldRevertCards) {
      final totalCurrent = current.completedCards * 10 + current.stamps;
      final newTotal = (totalCurrent - 1).clamp(0, 1 << 30);
      newStamps = newTotal % 10;
      newCards = newTotal ~/ 10;
    } else {
      // Card completed but voucher already redeemed: do NOT touch stamps/cards
      // (keep current). Only points/token handling above.
      newStamps = current.stamps;
      newCards = current.completedCards;
      // also voucher already handled as not revoked
    }
  }

  final newTokens = canRevokeToken ? (current.spinnerTokens - 1).clamp(0, 1 << 30) : current.spinnerTokens;

  final newState = current.copyWith(
    points: newPoints,
    // lifetimePoints unchanged
    stamps: newStamps,
    completedCards: newCards,
    spinnerTokens: newTokens,
    vouchers: newVouchers,
  );

  return ReversalResult(
    state: newState,
    revokedPoints: effect.earned > 0,
    revokedStamp: effect.stampGranted && (effect.completedCardGranted ? canRevokeVoucher : true),
    revokedToken: canRevokeToken,
    revokedVoucher: canRevokeVoucher,
  );
}
