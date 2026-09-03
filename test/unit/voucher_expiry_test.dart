import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/loyalty_state.dart';

void main() {
  group('Voucher expiry', () {
    test('isExpired true when past expiresAt', () {
      final v = Voucher(
        type: VoucherType.freeTopping,
        grantedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        id: '1',
      );
      expect(v.isExpired, isTrue);
    });

    test('isExpired false when future', () {
      final v = Voucher(
        type: VoucherType.freeDrink,
        grantedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 5)),
        id: '2',
      );
      expect(v.isExpired, isFalse);
      expect(v.isExpiringSoon, isFalse);
    });

    test('isExpiringSoon true within 2 days', () {
      final v = Voucher(
        type: VoucherType.freeSnack,
        grantedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 30)),
        id: '3',
      );
      expect(v.isExpiringSoon, isTrue);
    });

    test('fromJson handles legacy without id/expires_at', () {
      final v = Voucher.fromJson({'type': 'free_topping', 'at': '2026-01-01T00:00:00Z'});
      expect(v.type, VoucherType.freeTopping);
      expect(v.id, isNull);
      expect(v.expiresAt, isNull);
      expect(v.isExpired, isFalse);
    });

    test('fromJson parses new fields', () {
      final now = DateTime.now().toUtc();
      final v = Voucher.fromJson({
        'type': 'free_drink',
        'at': now.toIso8601String(),
        'id': 'abc',
        'expires_at': now.add(const Duration(days: 14)).toIso8601String(),
        'source': 'spinner',
      });
      expect(v.id, 'abc');
      expect(v.source, 'spinner');
      expect(v.expiresAt, isNotNull);
    });

    test('toJson round-trip includes new fields', () {
      final v = Voucher(
        type: VoucherType.freeSnack,
        grantedAt: DateTime.parse('2026-01-01T00:00:00Z'),
        id: 'xyz',
        expiresAt: DateTime.parse('2026-01-15T00:00:00Z'),
        source: 'card',
      );
      final j = v.toJson();
      expect(j['id'], 'xyz');
      expect(j['expires_at'], isNotNull);
      final r = Voucher.fromJson(j);
      expect(r.id, 'xyz');
      expect(r.expiresAt, isNotNull);
    });
  });
}
