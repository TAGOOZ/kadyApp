import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/loyalty_controller.dart';

void main() {
  group('derivedTier', () {
    test('bronze below 2000', () {
      expect(derivedTier(0), Tier.bronze);
      expect(derivedTier(1999), Tier.bronze);
    });
    test('silver at 2000..4999', () {
      expect(derivedTier(2000), Tier.silver);
      expect(derivedTier(4999), Tier.silver);
    });
    test('gold at 5000+', () {
      expect(derivedTier(5000), Tier.gold);
      expect(derivedTier(99999), Tier.gold);
    });
  });

  group('LoyaltyState json round-trip', () {
    test('parses supabase row shape', () {
      final s = LoyaltyState.fromJson({
        'points': 120,
        'lifetime_points': 2100,
        'stamps': 7,
        'completed_cards': 2,
        'spinner_tokens': 1,
        'match_tokens': 0,
        'scratch_tokens': 3,
        'double_next_order': true,
        'vouchers': [
          {'type': 'free_drink', 'at': '2026-08-22T10:00:00Z'},
        ],
      });
      expect(s.tier, Tier.silver);
      expect(s.points, 120);
      expect(s.vouchers.single.type, VoucherType.freeDrink);
    });
    test('voucher toJson/fromJson round trip', () {
      final v = Voucher(type: VoucherType.freeTopping, grantedAt: DateTime.parse('2026-01-01T00:00:00Z'));
      expect(Voucher.fromJson(v.toJson()).type, VoucherType.freeTopping);
    });
  });
}
