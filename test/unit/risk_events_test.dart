// Risk events ledger — RISK-02 (issue #47).
// Tests that mirror the SQL trigger sync_risk_profile() branching and
// idempotency, plus the Dart pure classification helper.
// No network, deterministic.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/risk_profile_repository.dart';
import 'package:kady_app/domain/risk_profile.dart';

void main() {
  group('classifyRiskEventType — status transition → event_type', () {
    test('new → done emits SUCCESSFUL_ORDER', () {
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'done'),
        RiskEventType.successfulOrder,
      );
      expect(
        classifyRiskEventType(oldStatus: 'accepted', newStatus: 'done'),
        RiskEventType.successfulOrder,
      );
      expect(
        classifyRiskEventType(oldStatus: 'out_for_delivery', newStatus: 'done'),
        RiskEventType.successfulOrder,
      );
    });

    test('no event for non-terminal statuses', () {
      expect(classifyRiskEventType(oldStatus: 'new', newStatus: 'accepted'), isNull);
      expect(classifyRiskEventType(oldStatus: 'accepted', newStatus: 'in_prep'), isNull);
      expect(classifyRiskEventType(oldStatus: 'in_prep', newStatus: 'ready'), isNull);
      expect(classifyRiskEventType(oldStatus: 'ready', newStatus: 'out_for_delivery'), isNull);
    });

    test('cancelled without reason defaults to CANCELLED_ORDER', () {
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled'),
        RiskEventType.cancelledOrder,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: ''),
        RiskEventType.cancelledOrder,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'unknown'),
        RiskEventType.cancelledOrder,
      );
    });

    test('cancelled + cancel reason → CANCELLED_ORDER (case-insensitive)', () {
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'customer cancelled'),
        RiskEventType.cancelledOrder,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'CANCELLED by user'),
        RiskEventType.cancelledOrder,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'User CANCELED order'),
        // note: 'cancel' substring still matches; 'canceled' contains 'cancel'
        RiskEventType.cancelledOrder,
      );
    });

    test('cancelled + refused|rejected → REJECTED_ORDER (case-insensitive)', () {
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'order refused by restaurant'),
        RiskEventType.rejectedOrder,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'REJECTED: fraud'),
        RiskEventType.rejectedOrder,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'Refused'),
        RiskEventType.rejectedOrder,
      );
    });

    test('cancelled vs rejected distinction — rejected takes priority over cancel', () {
      // reject_reason contains both 'cancel' and 'rejected' → must be REJECTED_ORDER
      expect(
        classifyRiskEventType(
          oldStatus: 'new',
          newStatus: 'cancelled',
          rejectReason: 'cancelled: order rejected due to verification',
        ),
        RiskEventType.rejectedOrder,
      );
      // same for refused + cancel
      expect(
        classifyRiskEventType(
          oldStatus: 'new',
          newStatus: 'cancelled',
          rejectReason: 'customer cancelled but also refused',
        ),
        RiskEventType.rejectedOrder,
      );
    });

    test('cancelled + failed delivery → FAILED_DELIVERY', () {
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'failed delivery'),
        RiskEventType.failedDelivery,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'Failed Delivery - address not found'),
        RiskEventType.failedDelivery,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'delivery failed due to timeout'),
        RiskEventType.failedDelivery,
      );
      expect(
        classifyRiskEventType(oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'failed_delivery'),
        RiskEventType.failedDelivery,
      );
    });

    test('failed delivery priority over generic cancel but after rejected', () {
      // contains both failed delivery and cancel → FAILED_DELIVERY (checked before cancel)
      expect(
        classifyRiskEventType(
          oldStatus: 'new',
          newStatus: 'cancelled',
          rejectReason: 'failed delivery - customer cancelled address',
        ),
        RiskEventType.failedDelivery,
      );
      // rejected still wins over failed delivery per SQL order (refused before failed)
      expect(
        classifyRiskEventType(
          oldStatus: 'new',
          newStatus: 'cancelled',
          rejectReason: 'refused: failed delivery claimed',
        ),
        RiskEventType.rejectedOrder,
      );
    });

    test('no duplicate on re-update with same status (idempotent guard)', () {
      expect(classifyRiskEventType(oldStatus: 'done', newStatus: 'done'), isNull);
      expect(classifyRiskEventType(oldStatus: 'cancelled', newStatus: 'cancelled', rejectReason: 'cancelled'), isNull);
      expect(classifyRiskEventType(oldStatus: 'new', newStatus: 'new'), isNull);
    });

    test('non-cancelled newStatus never emits even with rejectReason', () {
      expect(classifyRiskEventType(oldStatus: 'new', newStatus: 'done', rejectReason: 'rejected'), RiskEventType.successfulOrder);
      expect(classifyRiskEventType(oldStatus: 'new', newStatus: 'accepted', rejectReason: 'cancelled'), isNull);
    });
  });

  group('applyRiskEventToProfile — pure counter transition', () {
    test('done increments total + successful + spent', () {
      const p = RiskProfile(phone: 'x', totalOrders: 0, successfulOrders: 0, totalSpent: 100);
      final next = applyRiskEventToProfile(p, oldStatus: 'new', newStatus: 'done', orderTotal: 50);
      expect(next.totalOrders, 1);
      expect(next.successfulOrders, 1);
      expect(next.totalSpent, 150);
      expect(next.cancelledOrders, 0);
      expect(next.lastOrderAt, isNotNull);
    });

    test('cancelled increments cancelled', () {
      const p = RiskProfile(phone: 'x');
      final next = applyRiskEventToProfile(p, oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'customer cancelled');
      expect(next.totalOrders, 1);
      expect(next.cancelledOrders, 1);
      expect(next.rejectedOrders, 0);
    });

    test('cancelled with rejected increments rejected not cancelled', () {
      const p = RiskProfile(phone: 'x');
      final next = applyRiskEventToProfile(p, oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'order rejected');
      expect(next.rejectedOrders, 1);
      expect(next.cancelledOrders, 0);
    });

    test('cancelled with failed delivery increments failedDeliveries', () {
      const p = RiskProfile(phone: 'x');
      final next = applyRiskEventToProfile(p, oldStatus: 'new', newStatus: 'cancelled', rejectReason: 'failed delivery');
      expect(next.failedDeliveries, 1);
      expect(next.cancelledOrders, 0);
    });

    test('no transition for non-terminal leaves profile unchanged', () {
      const p = RiskProfile(phone: 'x', totalOrders: 5);
      final next = applyRiskEventToProfile(p, oldStatus: 'new', newStatus: 'accepted');
      expect(next.totalOrders, 5);
      expect(identical(p, next), isTrue);
    });

    test('idempotent guard: same status returns same instance', () {
      const p = RiskProfile(phone: 'x');
      final next = applyRiskEventToProfile(p, oldStatus: 'done', newStatus: 'done');
      expect(identical(p, next), isTrue);
    });
  });

  group('FakeRiskProfileRepo — offline seam', () {
    test('fetchProfile returns seeded profile', () async {
      const seeded = RiskProfile(phone: '+201000000000', totalOrders: 3, successfulOrders: 2);
      final repo = FakeRiskProfileRepo();
      repo.seedProfile(seeded);
      final got = await repo.fetchProfile('+201000000000');
      expect(got, isNotNull);
      expect(got!.totalOrders, 3);
      expect(got.successfulOrders, 2);
      expect(await repo.fetchProfile('+209999999999'), isNull);
    });

    test('fetchRecentEvents respects limit and newest-first order', () async {
      final repo = FakeRiskProfileRepo();
      final phone = '+201000000000';
      repo.seedEvents(phone, [
        RiskEvent(id: 1, eventType: 'CANCELLED_ORDER', createdAt: DateTime.utc(2026, 8, 24)),
        RiskEvent(id: 2, eventType: 'SUCCESSFUL_ORDER', createdAt: DateTime.utc(2026, 8, 25)),
        RiskEvent(id: 3, eventType: 'REJECTED_ORDER', createdAt: DateTime.utc(2026, 8, 23)),
      ]);
      final recentTwo = await repo.fetchRecentEvents(phone, limit: 2);
      expect(recentTwo.map((e) => e.id).toList(), [2, 1]); // newest first, limit 2
      final all = await repo.fetchRecentEvents(phone);
      expect(all.length, 3);
    });

    test('empty phone returns empty list', () async {
      final repo = FakeRiskProfileRepo();
      expect(await repo.fetchRecentEvents('+200000000000'), isEmpty);
    });
  });
}
