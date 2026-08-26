// Pure risk profile helpers — RISK-02 (issue #47).
// No network, no Supabase — deterministic only.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/risk_engine.dart';
import 'package:kady_app/domain/risk_profile.dart';

void main() {
  group('RiskProfile.fromRow — parsing + fallbacks', () {
    test('parses full row', () {
      final p = RiskProfile.fromRow({
        'phone': '+201111111111',
        'total_orders': 3,
        'successful_orders': 2,
        'cancelled_orders': 1,
        'failed_deliveries': 0,
        'rejected_orders': 0,
        'total_spent': 450,
        'last_order_at': '2026-08-25T10:00:00Z',
        'phone_verified': true,
        'risk_score': 15,
        'risk_level': 'low',
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-25T10:00:00Z',
      });
      expect(p.phone, '+201111111111');
      expect(p.totalOrders, 3);
      expect(p.successfulOrders, 2);
      expect(p.cancelledOrders, 1);
      expect(p.totalSpent, 450);
      expect(p.phoneVerified, isTrue);
      expect(p.riskScore, 15);
      expect(p.riskLevel, RiskLevel.low);
      expect(p.lastOrderAt, isNotNull);
    });

    test('fallbacks to 0/false when keys missing or string numbers', () {
      final p = RiskProfile.fromRow({
        'phone': '+201222222222',
        'total_orders': '5',
        'successful_orders': null,
      });
      expect(p.totalOrders, 5);
      expect(p.successfulOrders, 0);
      expect(p.cancelledOrders, 0);
      expect(p.phoneVerified, isFalse);
      expect(p.riskLevel, isNull);
      expect(p.riskScore, 0);
    });

    test('parses bool strings and ints', () {
      final t1 = RiskProfile.fromRow({'phone': 'x', 'phone_verified': 'true'});
      expect(t1.phoneVerified, isTrue);
      final t2 = RiskProfile.fromRow({'phone': 'x', 'phone_verified': 1});
      expect(t2.phoneVerified, isTrue);
      final f = RiskProfile.fromRow({'phone': 'x', 'phone_verified': false});
      expect(f.phoneVerified, isFalse);
    });

    test('unknown risk_level yields null (historic nullable)', () {
      final p = RiskProfile.fromRow({'phone': 'x', 'risk_level': 'unknown'});
      expect(p.riskLevel, isNull);
      final q = RiskProfile.fromRow({'phone': 'x'});
      expect(q.riskLevel, isNull);
    });

    test('toRow round-trips wireName', () {
      const p = RiskProfile(
        phone: '+201333333333',
        totalOrders: 1,
        riskScore: 20,
        riskLevel: RiskLevel.medium,
        phoneVerified: true,
      );
      final row = p.toRow();
      expect(row['phone'], '+201333333333');
      expect(row['total_orders'], 1);
      expect(row['risk_level'], 'medium');
      expect(row['phone_verified'], isTrue);
      final back = RiskProfile.fromRow(row);
      expect(back.phone, p.phone);
      expect(back.totalOrders, p.totalOrders);
      expect(back.riskLevel, RiskLevel.medium);
    });
  });

  group('RiskProfile predicates — new vs returning thresholds', () {
    test('isNewCustomer true when total_orders==0, false otherwise', () {
      const fresh = RiskProfile(phone: 'x', totalOrders: 0);
      const returning = RiskProfile(phone: 'x', totalOrders: 1);
      expect(isNewCustomer(fresh), isTrue);
      expect(isNewCustomer(returning), isFalse);
      expect(isReturningCustomer(fresh), isFalse);
      expect(isReturningCustomer(returning), isTrue);
    });

    test('hasThreePlusCancellations threshold >=3', () {
      const two = RiskProfile(phone: 'x', cancelledOrders: 2);
      const three = RiskProfile(phone: 'x', cancelledOrders: 3);
      const five = RiskProfile(phone: 'x', cancelledOrders: 5);
      expect(hasThreePlusCancellations(two), isFalse);
      expect(hasThreePlusCancellations(three), isTrue);
      expect(hasThreePlusCancellations(five), isTrue);
    });

    test('hasPreviousFailedDelivery / hasFailedDeliveries', () {
      const none = RiskProfile(phone: 'x', failedDeliveries: 0);
      const one = RiskProfile(phone: 'x', failedDeliveries: 1);
      expect(hasPreviousFailedDelivery(none), isFalse);
      expect(hasPreviousFailedDelivery(one), isTrue);
      expect(hasFailedDeliveries(one), isTrue);
    });

    test('hasPreviousRejectedOrder / hasRejectedOrders', () {
      const none = RiskProfile(phone: 'x', rejectedOrders: 0);
      const one = RiskProfile(phone: 'x', rejectedOrders: 2);
      expect(hasPreviousRejectedOrder(none), isFalse);
      expect(hasPreviousRejectedOrder(one), isTrue);
      expect(hasRejectedOrders(one), isTrue);
    });

    test('hasThreePlusSuccessful vs hasFivePlusSuccessful', () {
      const two = RiskProfile(phone: 'x', successfulOrders: 2);
      const three = RiskProfile(phone: 'x', successfulOrders: 3);
      const five = RiskProfile(phone: 'x', successfulOrders: 5);
      const four = RiskProfile(phone: 'x', successfulOrders: 4);
      expect(hasThreePlusSuccessful(two), isFalse);
      expect(hasThreePlusSuccessful(three), isTrue);
      expect(hasThreePlusSuccessful(four), isTrue);
      expect(hasFivePlusSuccessful(four), isFalse);
      expect(hasFivePlusSuccessful(five), isTrue);
      // 5+ implies 3+ as per business rule (but helper is independent)
      expect(hasThreePlusSuccessful(five), isTrue);
    });

    test('isVerifiedPhone / hasVerifiedPhone', () {
      const unverified = RiskProfile(phone: 'x', phoneVerified: false);
      const verified = RiskProfile(phone: 'x', phoneVerified: true);
      expect(isVerifiedPhone(unverified), isFalse);
      expect(isVerifiedPhone(verified), isTrue);
      expect(hasVerifiedPhone(verified), isTrue);
    });
  });

  group('RiskProfile → RiskContext bridge', () {
    test('riskContextFromProfile maps counters correctly', () {
      const profile = RiskProfile(
        phone: '+201000000000',
        totalOrders: 4,
        successfulOrders: 3,
        cancelledOrders: 3,
        failedDeliveries: 1,
        rejectedOrders: 1,
        phoneVerified: true,
      );
      final ctx = riskContextFromProfile(
        profile,
        subtotalEgp: 600,
        isNewDevice: true,
        isLargeOrder: true,
        isRapidOrders: false,
      );
      expect(ctx.isNewCustomer, isFalse); // total_orders 4 → returning
      expect(ctx.cancellationsCount, 3);
      expect(ctx.previousFailedDeliveries, 1);
      expect(ctx.previousRejectedOrders, 1);
      expect(ctx.successfulOrders, 3);
      expect(ctx.isVerifiedPhone, isTrue);
      expect(ctx.isNewDevice, isTrue);
      expect(ctx.subtotalEgp, 600);
      expect(ctx.isLargeOrder, isTrue);
    });

    test('new profile yields isNewCustomer true', () {
      const fresh = RiskProfile(phone: 'x', totalOrders: 0);
      final ctx = riskContextFromProfile(fresh);
      expect(ctx.isNewCustomer, isTrue);
      expect(ctx.cancellationsCount, 0);
      expect(ctx.successfulOrders, 0);
    });
  });

  group('RiskEvent.fromRow — parsing', () {
    test('parses full row', () {
      final e = RiskEvent.fromRow({
        'id': 42,
        'phone': '+201111111111',
        'order_id': 'ord-uuid',
        'device_id': 'dev-123',
        'event_type': 'SUCCESSFUL_ORDER',
        'metadata': {'old_status': 'new', 'new_status': 'done'},
        'created_at': '2026-08-25T10:00:00Z',
      });
      expect(e.id, 42);
      expect(e.phone, '+201111111111');
      expect(e.orderId, 'ord-uuid');
      expect(e.deviceId, 'dev-123');
      expect(e.eventType, 'SUCCESSFUL_ORDER');
      expect(e.metadata['new_status'], 'done');
      expect(e.createdAt, isNotNull);
    });

    test('tolerates string id and missing metadata', () {
      final e = RiskEvent.fromRow({'id': '7', 'event_type': 'CANCELLED_ORDER'});
      expect(e.id, 7);
      expect(e.metadata, isEmpty);
    });

    test('keeps UTC for timestamps', () {
      final p = RiskProfile.fromRow({
        'phone': '+201000000001',
        'last_order_at': '2026-08-25T10:00:00Z',
        'created_at': DateTime.utc(2026, 8, 25, 10, 0, 0),
      });
      expect(p.lastOrderAt!.isUtc, isTrue);
      expect(p.createdAt!.isUtc, isTrue);
      final e = RiskEvent.fromRow({
        'id': 1,
        'event_type': 'SUCCESSFUL_ORDER',
        'created_at': '2026-08-25T10:00:00Z',
      });
      expect(e.createdAt!.isUtc, isTrue);
    });
  });

  group('RiskProfile — review fixes', () {
    test('fromRow throws on missing/empty phone', () {
      expect(() => RiskProfile.fromRow({}), throwsArgumentError);
      expect(() => RiskProfile.fromRow({'phone': ''}), throwsArgumentError);
      expect(() => RiskProfile.fromRow({'phone': '   '}), throwsArgumentError);
    });

    test('toRow emits UTC ISO strings with Z', () {
      final when = DateTime.utc(2026, 8, 25, 10, 0, 0);
      const p = RiskProfile(phone: '+201000000002');
      final withTime = p.copyWith(lastOrderAt: when, createdAt: when, updatedAt: when);
      final row = withTime.toRow();
      expect(row['last_order_at'], '2026-08-25T10:00:00.000Z');
      expect(row['created_at'], '2026-08-25T10:00:00.000Z');
      // round-trip preserves UTC
      final back = RiskProfile.fromRow(row);
      expect(back.lastOrderAt!.isUtc, isTrue);
      expect(back.lastOrderAt, when);
    });

    test('equality includes lastOrderAt/createdAt/updatedAt', () {
      final t1 = DateTime.utc(2026, 8, 25, 10, 0, 0);
      final t2 = DateTime.utc(2026, 8, 25, 11, 0, 0);
      const base = RiskProfile(phone: '+201000000003', totalOrders: 1);
      final a = base.copyWith(lastOrderAt: t1);
      final b = base.copyWith(lastOrderAt: t2);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
      final c = base.copyWith(lastOrderAt: t1, createdAt: t1);
      final d = base.copyWith(lastOrderAt: t1, createdAt: t2);
      expect(c == d, isFalse);
    });

    test('copyWith can clear nullable DateTime to null via sentinel', () {
      final p = RiskProfile(
        phone: '+201000000004',
        lastOrderAt: DateTime.utc(2026, 8, 25),
        riskLevel: RiskLevel.low,
      );
      final cleared = p.copyWith(lastOrderAt: null, riskLevel: null);
      expect(cleared.lastOrderAt, isNull);
      expect(cleared.riskLevel, isNull);
      expect(cleared.phone, p.phone);
    });

    test('intFor rounds double string (e.g. "5.0" → 5, "5.6" → 6)', () {
      final p1 = RiskProfile.fromRow({'phone': '+201000000005', 'total_orders': '5.0'});
      expect(p1.totalOrders, 5);
      final p2 = RiskProfile.fromRow({'phone': '+201000000006', 'total_orders': '5.6'});
      expect(p2.totalOrders, 6);
      final p3 = RiskProfile.fromRow({'phone': '+201000000007', 'total_orders': 5.6});
      expect(p3.totalOrders, 6);
    });

    test('applyRiskEventToProfile deterministic with injected nowUtc', () {
      const p = RiskProfile(phone: '+201000000008');
      final fixed = DateTime.utc(2026, 8, 25, 12, 0, 0);
      final a = applyRiskEventToProfile(
        p,
        oldStatus: 'new',
        newStatus: 'done',
        orderTotal: 100,
        nowUtc: fixed,
      );
      final b = applyRiskEventToProfile(
        p,
        oldStatus: 'new',
        newStatus: 'done',
        orderTotal: 100,
        nowUtc: fixed,
      );
      expect(a.lastOrderAt, fixed);
      expect(a == b, isTrue);
      expect(a.totalOrders, 1);
      expect(a.successfulOrders, 1);
      expect(a.totalSpent, 100);
    });
  });
}
