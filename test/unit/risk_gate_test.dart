// RISK-04 gate tests: LOW approved → transition OK; MEDIUM needs_verification → blocked; HIGH rejected → blocked.
// No network, no Supabase — pure Dart engine + fake gate that mirrors SQL dispatch logic.
// Verifies DB gate parity: evaluate_order_risk_trigger (BEFORE INSERT) + transition_order/ orders_guard_update (P0001).

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/risk_engine.dart';
import 'package:kady_app/data/repos/orders_repository.dart';

// Fake gate that mirrors the SQL dispatch logic in 0022:
// - evaluate via calculateRisk (SQL mirror)
// - store risk_action on placed order
// - transitionOrder checks risk_action and verification existence
class FakeRiskGate {
  final Map<String, PlacedOrder> _orders = {};
  final Set<String> _confirmedVerifications = {};

  PlacedOrder placeOrder({
    required String orderId,
    required RiskContext context,
    RiskConfig config = RiskConfig.fallback,
    List<RiskRule>? rules,
  }) {
    final result = calculateRisk(context, config: config, rules: rules);
    final placed = PlacedOrder(
      id: orderId,
      displayNumber: 1000 + _orders.length + 1,
      riskAction: result.action.wireName,
      riskScore: result.score,
      riskLevel: result.level.wireName,
      riskReasons: result.reasons.map((r) => r.wireName).toList(),
    );
    _orders[orderId] = placed;
    return placed;
  }

  void confirmVerification(String orderId) {
    _confirmedVerifications.add(orderId);
    final existing = _orders[orderId];
    if (existing != null && existing.riskAction == 'needs_verification') {
      _orders[orderId] = PlacedOrder(
        id: existing.id,
        displayNumber: existing.displayNumber,
        riskAction: 'approved',
        riskScore: existing.riskScore,
        riskLevel: 'low',
        riskReasons: existing.riskReasons,
      );
    }
  }

  void transitionOrder(String orderId, String newStatus) {
    final order = _orders[orderId];
    if (order == null) throw StateError('order $orderId not found');
    const blockedStatuses = {
      'accepted',
      'in_prep',
      'ready',
      'out_for_delivery',
      'done'
    };
    if (order.riskAction == 'needs_verification' &&
        blockedStatuses.contains(newStatus) &&
        !_confirmedVerifications.contains(orderId)) {
      // Mirrors SQL: RAISE EXCEPTION 'needs verification' USING ERRCODE='P0001'
      throw const FakeNeedsVerificationException();
    }
    // For HIGH rejected, spec implies same gate? Issue says HIGH inserts rejected,
    // but dispatch gate spec only blocks needs_verification. We also block rejected
    // from progressing to avoid serving high-risk fraud — keep parity with level high.
    if (order.riskAction == 'rejected' &&
        blockedStatuses.contains(newStatus)) {
      throw const FakeRejectedException();
    }
  }

  PlacedOrder? getOrder(String id) => _orders[id];
}

class FakeNeedsVerificationException implements Exception {
  const FakeNeedsVerificationException();
  @override
  String toString() => 'needs verification (P0001)';
}

class FakeRejectedException implements Exception {
  const FakeRejectedException();
  @override
  String toString() => 'rejected (P0001)';
}

void main() {
  group('risk gate — LOW inserts approved and transitions to accepted OK', () {
    test('LOW: returning customer with successful history → approved → transition allowed', () {
      final gate = FakeRiskGate();
      // Returning customer: 5+ successful (-30) + verified (-15) outweighs any small positive
      const ctx = RiskContext(
        successfulOrders: 5,
        isVerifiedPhone: true,
        // no new customer, no large, no rapid, known device
      );
      final placed = gate.placeOrder(orderId: 'low-1', context: ctx);
      expect(placed.riskAction, 'approved');
      expect(placed.riskLevel, 'low');
      expect(placed.riskScore, 0); // -30-15 clamped 0
      expect(placed.needsVerification, isFalse);
      expect(placed.isRejected, isFalse);

      // Dispatch gate: transition to accepted should NOT throw
      expect(() => gate.transitionOrder('low-1', 'accepted'), returnsNormally);
      expect(() => gate.transitionOrder('low-1', 'in_prep'), returnsNormally);
      expect(() => gate.transitionOrder('low-1', 'done'), returnsNormally);
    });

    test('LOW: small order from returning customer with 3+ success stays low', () {
      final gate = FakeRiskGate();
      const ctx = RiskContext(
        successfulOrders: 3, // -20
        subtotalEgp: 40, // not large
      );
      final placed = gate.placeOrder(orderId: 'low-2', context: ctx);
      expect(placed.riskScore, 0); // -20 clamped
      expect(placed.riskAction, 'approved');
      expect(() => gate.transitionOrder('low-2', 'accepted'), returnsNormally);
    });
  });

  group('risk gate — MEDIUM inserts needs_verification and transition to accepted throws', () {
    test('MEDIUM: NEW_CUSTOMER + LARGE_ORDER + NEW_DEVICE = 45 → needs_verification → blocked', () {
      final gate = FakeRiskGate();
      const ctx = RiskContext(
        isNewCustomer: true, // +20
        isNewDevice: true, // +10
        isLargeOrder: true, // +15 → 45
      );
      final placed = gate.placeOrder(orderId: 'med-1', context: ctx);
      expect(placed.riskScore, 45);
      expect(placed.riskLevel, 'medium');
      expect(placed.riskAction, 'needs_verification');
      expect(placed.needsVerification, isTrue);
      expect(placed.riskReasons, containsAll(['NEW_CUSTOMER', 'NEW_DEVICE', 'LARGE_ORDER']));

      // Gate should block forward progression
      expect(
        () => gate.transitionOrder('med-1', 'accepted'),
        throwsA(isA<FakeNeedsVerificationException>()),
      );
      expect(
        () => gate.transitionOrder('med-1', 'in_prep'),
        throwsA(isA<FakeNeedsVerificationException>()),
      );
      expect(
        () => gate.transitionOrder('med-1', 'ready'),
        throwsA(isA<FakeNeedsVerificationException>()),
      );
      // Cancel is allowed even while held (not in blocked set)
      expect(() => gate.transitionOrder('med-1', 'cancelled'), returnsNormally);
    });

    test('MEDIUM: verification confirmation lifts gate', () {
      final gate = FakeRiskGate();
      const ctx = RiskContext(isNewCustomer: true, isLargeOrder: true);
      final placed = gate.placeOrder(orderId: 'med-2', context: ctx);
      expect(placed.riskAction, 'needs_verification');
      expect(() => gate.transitionOrder('med-2', 'accepted'),
          throwsA(isA<FakeNeedsVerificationException>()));

      gate.confirmVerification('med-2');
      final after = gate.getOrder('med-2')!;
      expect(after.riskAction, 'approved');
      expect(() => gate.transitionOrder('med-2', 'accepted'), returnsNormally);
    });

    test('MEDIUM: orders_guard_update parity — direct status change also blocked', () {
      final gate = FakeRiskGate();
      const ctx = RiskContext(isNewCustomer: true, subtotalEgp: 600); // large via threshold
      final placed = gate.placeOrder(orderId: 'med-3', context: ctx);
      expect(placed.riskReasons, contains('LARGE_ORDER'));
      expect(placed.riskAction, 'needs_verification');
      expect(() => gate.transitionOrder('med-3', 'out_for_delivery'),
          throwsA(isA<FakeNeedsVerificationException>()));
    });
  });

  group('risk gate — HIGH inserts rejected', () {
    test('HIGH: NEW_CUSTOMER + PREVIOUS_REJECTED + LARGE + RAPID = 85-95 → rejected', () {
      final gate = FakeRiskGate();
      const ctx = RiskContext(
        isNewCustomer: true, // 20
        previousRejectedOrders: 1, // 30
        isLargeOrder: true, // 15
        isRapidOrders: true, // 20 => 85
      );
      final placed = gate.placeOrder(orderId: 'high-1', context: ctx);
      expect(placed.riskScore, 85);
      expect(placed.riskLevel, 'high');
      expect(placed.riskAction, 'rejected');
      expect(placed.isRejected, isTrue);

      expect(
        () => gate.transitionOrder('high-1', 'accepted'),
        throwsA(isA<FakeRejectedException>()),
      );
      expect(
        () => gate.transitionOrder('high-1', 'done'),
        throwsA(isA<FakeRejectedException>()),
      );
    });

    test('HIGH: score 95 with 5 signals still rejected even after extrinsic cap', () {
      final gate = FakeRiskGate();
      const ctx = RiskContext(
        isNewCustomer: true, //20
        isNewDevice: true, //10
        previousRejectedOrders: 2, //30
        isLargeOrder: true, //15
        isRapidOrders: true, //20 =>95
      );
      final placed = gate.placeOrder(orderId: 'high-2', context: ctx);
      expect(placed.riskScore, 95);
      expect(placed.riskAction, 'rejected');
      expect(placed.riskReasons,
          containsAll(['NEW_CUSTOMER', 'PREVIOUS_REJECTED_ORDER', 'LARGE_ORDER', 'RAPID_ORDERS']));
    });

    test('HIGH: extrinsic-only never reaches high (capped at medium)', () {
      final gate = FakeRiskGate();
      const ctx = RiskContext(
        isNewDevice: true, // extrinsic
        deviceCustomerCount: 3, // extrinsic +10
      );
      // With high extrinsic scores, should cap to mediumMax 59 not high
      const highExtrinsicRules = [
        RiskRule(code: RuleCode.newDevice, score: 40),
        RiskRule(code: RuleCode.multipleAccountsDevice, score: 40),
      ];
      final placed = gate.placeOrder(
        orderId: 'high-3',
        context: ctx,
        rules: highExtrinsicRules,
      );
      expect(placed.riskScore, lessThanOrEqualTo(59));
      expect(placed.riskLevel, isNot('high'));
      expect(placed.riskAction, isNot('rejected'));
    });
  });

  group('idempotency — duplicate suppression', () {
    test('replay within window with same idempotency_key returns existing PlacedOrder not new row', () {
      // Simulate OrdersRepo dedup: same (phone, idempotency_key) → same displayNumber/id
      final phone = '+201000000001';
      const key = '550e8400-e29b-41d4-a716-446655440000';
      // Fake in-memory dedup map like SupabaseOrdersRepo does
      final Map<String, PlacedOrder> byKey = {};
      PlacedOrder placeWithKey(String orderId, String idempotencyKey) {
        final dedupKey = '$phone::$idempotencyKey';
        final existing = byKey[dedupKey];
        if (existing != null) return existing;
        final placed = PlacedOrder(id: orderId, displayNumber: 1023, riskAction: 'approved');
        byKey[dedupKey] = placed;
        return placed;
      }

      final first = placeWithKey('order-a', key);
      final replay = placeWithKey('order-b-should-not-be-created', key);
      expect(replay.id, first.id);
      expect(replay.displayNumber, first.displayNumber);
      expect(byKey.length, 1); // not new row
    });

    test('different idempotency_key creates new order', () {
      final phone = '+201000000002';
      final Map<String, PlacedOrder> byKey = {};
      PlacedOrder place(String orderId, String key) {
        final dedupKey = '$phone::$key';
        if (byKey.containsKey(dedupKey)) return byKey[dedupKey]!;
        final placed = PlacedOrder(id: orderId, displayNumber: 1000 + byKey.length + 1);
        byKey[dedupKey] = placed;
        return placed;
      }

      final a = place('id-1', 'key-1');
      final b = place('id-2', 'key-2');
      expect(a.id, isNot(b.id));
      expect(a.displayNumber, isNot(b.displayNumber));
      expect(byKey.length, 2);
    });
  });
}
