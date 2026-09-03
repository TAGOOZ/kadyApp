import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/loyalty_reversal.dart';
import 'package:kady_app/domain/loyalty_state.dart';

LoyaltyState _s({
  int points = 0,
  int lifetime = 0,
  int stamps = 0,
  int cards = 0,
  int tokens = 0,
  List<Voucher> vouchers = const [],
}) =>
    LoyaltyState(
      points: points,
      lifetimePoints: lifetime,
      stamps: stamps,
      completedCards: cards,
      spinnerTokens: tokens,
      vouchers: vouchers,
    );

void main() {
  group('reverseLoyalty — causal, never blindly stamps--', () {
    test('points only: non-qualifying order deducts points, lifetime untouched', () {
      final cur = _s(points: 20, lifetime: 100, stamps: 2);
      final eff = OrderEffect(orderId: 'o1', earned: 5, stampGranted: false, tokenGranted: false, completedCardGranted: false);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.points, 15);
      expect(r.state.lifetimePoints, 100);
      expect(r.state.stamps, 2);
      expect(r.revokedPoints, true);
      expect(r.revokedStamp, false);
    });

    test('blind stamp protection: isReversed=true does nothing', () {
      final cur = _s(points: 10, stamps: 3);
      final eff = OrderEffect(orderId: 'o1', earned: 5, stampGranted: true, tokenGranted: false, completedCardGranted: false, isReversed: true);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.points, 10);
      expect(r.state.stamps, 3);
    });

    test('simple stamp revert 2->3 token case: removes stamp and token if unused', () {
      // Current after A (2->3 token) : stamps3 tokens1
      final cur = _s(stamps: 3, tokens: 1);
      final eff = OrderEffect(orderId: 'A', earned: 5, stampGranted: true, stampBefore: 2, stampAfter: 3, tokenGranted: true, tokenPosition: 3, completedCardGranted: false);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.stamps, 2);
      expect(r.state.completedCards, 0);
      expect(r.state.spinnerTokens, 0);
      expect(r.revokedToken, true);
      expect(r.revokedStamp, true);
    });

    test('token already consumed: do NOT revoke token', () {
      // A granted token at 3, but current tokens 0 (already used via play)
      final cur = _s(stamps: 4, tokens: 0); // stamps 4 after B 3->4
      final eff = OrderEffect(orderId: 'A', earned: 5, stampGranted: true, stampBefore: 2, stampAfter: 3, tokenGranted: true, tokenPosition: 3, completedCardGranted: false);
      final r = reverseLoyalty(cur, eff);
      // total current 4 -> newTotal 3 => stamps3
      expect(r.state.stamps, 3);
      expect(r.state.spinnerTokens, 0, reason: 'token already redeemed, keep 0');
      expect(r.revokedToken, false);
      expect(r.revokedStamp, true);
    });

    test('9->10 card completion: reverts via total method to 9 if voucher unused', () {
      // Before A 9, after A 0 cards1 voucher. Current after A alone: stamps0 cards1 voucher present
      final voucherAt = DateTime.parse('2026-01-01T00:00:00Z');
      final cur = _s(stamps: 0, cards: 1, vouchers: [Voucher(type: VoucherType.freeSnack, grantedAt: voucherAt)]);
      final eff = OrderEffect(
          orderId: 'A', earned: 5, stampGranted: true, stampBefore: 9, stampAfter: 0,
          tokenGranted: false, completedCardGranted: true,
          voucherGrantedType: 'free_snack', voucherAt: voucherAt);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.stamps, 9);
      expect(r.state.completedCards, 0);
      expect(r.state.vouchers, isEmpty);
      expect(r.revokedVoucher, true);
    });

    test('card voucher already redeemed: keep card and stamps', () {
      // A 9->0 card voucher, then B redeemed voucher, so current has no voucher but cards1 stamps1 (after B)
      // Cancel A: voucher not found -> do NOT revert stamps/cards
      final voucherAt = DateTime.parse('2026-01-01T00:00:00Z');
      final cur = _s(stamps: 1, cards: 1, vouchers: []); // voucher already consumed, plus B 0->1
      final eff = OrderEffect(
          orderId: 'A', earned: 5, stampGranted: true, stampBefore: 9, stampAfter: 0,
          tokenGranted: false, completedCardGranted: true,
          voucherGrantedType: 'free_snack', voucherAt: voucherAt);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.stamps, 1, reason: 'keep stamps when voucher already redeemed');
      expect(r.state.completedCards, 1);
      expect(r.revokedVoucher, false);
      expect(r.revokedStamp, false);
    });

    test('example from audit: 9 stamps -> A gives voucher -> B happens -> voucher redeemed -> cancel A', () {
      // Initial 9, A 9->0 voucher, B 0->1, voucher redeemed (B not relevant), current stamps1 cards1 no voucher
      // Per edge test above, cancel A should keep
      final voucherAt = DateTime.parse('2026-01-01T00:00:00Z');
      final cur = _s(points: 15, stamps: 1, cards: 1, vouchers: []);
      final eff = OrderEffect(orderId: 'A', earned: 10, stampGranted: true, stampBefore: 9, stampAfter: 0,
          tokenGranted: false, completedCardGranted: true, voucherGrantedType: 'free_snack', voucherAt: voucherAt);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.points, 5);
      expect(r.state.stamps, 1);
      expect(r.state.completedCards, 1);
      expect(r.revokedVoucher, false);
    });

    test('subsequent order preserved when canceling earlier non-card', () {
      // 2->3 token (A), then 3->4 (B). Current 4. Cancel A -> expect 3 (not 2)
      // total method: totalCurrent 4 -> newTotal 3 => stamps3. Correct preserves B's effect as shift.
      final cur = _s(stamps: 4, tokens: 1); // after A token and B, but token already maybe? Let's say tokens1 (one net)
      final eff = OrderEffect(orderId: 'A', earned: 5, stampGranted: true, stampBefore: 2, stampAfter: 3, tokenGranted: true, tokenPosition: 3, completedCardGranted: false);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.stamps, 3);
      // token revoke? current tokens1 >0 so revoke true -> tokens0, but B from 3->4 would not grant token, so final 0 correct
      expect(r.state.spinnerTokens, 0);
    });

    test('never blindly tokens-- without causal: non-token order cancel does not touch tokens', () {
      final cur = _s(stamps: 5, tokens: 2);
      final eff = OrderEffect(orderId: 'X', earned: 5, stampGranted: true, stampBefore: 4, stampAfter: 5, tokenGranted: false, completedCardGranted: false);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.spinnerTokens, 2);
      expect(r.revokedToken, false);
      expect(r.state.stamps, 4);
    });

    test('lifetime never decrements on any reversal', () {
      final cur = _s(points: 100, lifetime: 500, stamps: 5);
      final eff = OrderEffect(orderId: 'o', earned: 50, stampGranted: true, stampBefore: 4, stampAfter: 5, tokenGranted: false, completedCardGranted: false);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.lifetimePoints, 500);
      expect(r.state.points, 50);
    });

    test('points clamp at 0 if already spent', () {
      final cur = _s(points: 10, lifetime: 100);
      final eff = OrderEffect(orderId: 'o', earned: 20, stampGranted: false, tokenGranted: false, completedCardGranted: false);
      final r = reverseLoyalty(cur, eff);
      expect(r.state.points, 0);
    });
  });
}
