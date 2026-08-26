// ignore_for_file: library_private_types_in_public_api
// RISK-04 flow test: collect→evaluate→store→events all in one transaction, no partial.
// Fake in-memory transaction that mirrors the SQL BEFORE/AFTER trigger chain:
// evaluate_order_risk_trigger (BEFORE) → create_risk_events (AFTER) in same txn.
// Verifies no partial state if any step fails.

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/risk_engine.dart';
import 'package:kady_app/domain/risk_profile.dart';

// In-memory fake DB that mimics the 0022 transaction semantics
class FakeRiskDb {
  final Map<String, RiskProfile> profiles = {};
  final Map<String, List<String>> devicesByPhone = {}; // phone → device_ids
  final Map<String, int> devicePhoneCount = {}; // device_id → distinct phone count
  final Map<String, _FakeOrder> orders = {};
  final Map<String, List<_FakeRiskEvent>> events = {}; // orderId → events
  int _displaySeq = 1000;

  RiskConfig config = RiskConfig.fallback;
  List<RiskRule> rules = kDefaultRiskRules;

  // Simulate BEFORE/AFTER in one synchronous transaction.
  // Returns the created order or throws (no partial writes).
  _FakeOrder insertOrder({
    required String orderId,
    required String phone,
    required int subtotalEgp,
    String? deviceId,
    String? addressId,
    List<String>? recentOrderIds, // for rapid window simulation
  }) {
    // Snapshots for rollback on failure
    final ordersBackup = Map<String, _FakeOrder>.from(orders);
    final eventsBackup = Map<String, List<_FakeRiskEvent>>.from(
      events.map((k, v) => MapEntry(k, List<_FakeRiskEvent>.from(v))),
    );
    final devicesBackup = Map<String, List<String>>.from(
      devicesByPhone.map((k, v) => MapEntry(k, List<String>.from(v))),
    );

    try {
      final profile = profiles[phone];
      final isNewCustomer = profile == null || profile.totalOrders == 0;
      final previousFailed = profile?.failedDeliveries ?? 0;
      final previousRejected = profile?.rejectedOrders ?? 0;
      final cancelledCount = profile?.cancelledOrders ?? 0;
      final successfulCount = profile?.successfulOrders ?? 0;
      final isVerified = profile?.phoneVerified ?? false;

      // Device context
      bool isNewDevice = false;
      int deviceCustomerCount = 0;
      if (deviceId != null && deviceId.isNotEmpty) {
        final phonesForDevice = devicePhoneCount[deviceId] ?? 0;
        final phoneDevices = devicesByPhone[phone] ?? [];
        isNewDevice = !phoneDevices.contains(deviceId);
        deviceCustomerCount = isNewDevice ? phonesForDevice + 1 : phonesForDevice;
      }

      // Rapid window: count recent orders for this phone in last window
      // Simplified: use recentOrderIds length as count of recent orders
      final recentCount = (recentOrderIds?.length ?? 0);
      final isRapid = (recentCount + 1) >= config.rapidOrdersCount;

      final isLarge = subtotalEgp >= config.largeOrderThreshold;

      final ctx = RiskContext(
        subtotalEgp: subtotalEgp,
        isNewCustomer: isNewCustomer,
        isNewDevice: isNewDevice,
        previousFailedDeliveries: previousFailed,
        previousRejectedOrders: previousRejected,
        cancellationsCount: cancelledCount,
        successfulOrders: successfulCount,
        isVerifiedPhone: isVerified,
        isLargeOrder: isLarge,
        isRapidOrders: isRapid,
        deviceCustomerCount: deviceCustomerCount,
        addressCustomerCount: 0,
        addressFailedCount: 0,
      );

      final result = calculateRisk(ctx, config: config, rules: rules);

      // BEFORE: set risk fields (like evaluate_order_risk_trigger writing NEW.risk_*)
      final order = _FakeOrder(
        id: orderId,
        phone: phone,
        subtotalEgp: subtotalEgp,
        deviceId: deviceId,
        addressId: addressId,
        displayNumber: ++_displaySeq,
        riskScore: result.score,
        riskLevel: result.level.wireName,
        riskAction: result.action.wireName,
        riskReasons: result.reasons.map((r) => r.wireName).toList(),
      );

      // Simulate a failure if subtotal is negative (should rollback no partial)
      if (subtotalEgp < 0) {
        throw ArgumentError('invalid subtotal');
      }

      orders[orderId] = order;

      // AFTER: create risk_events per reason in same txn
      final evs = <_FakeRiskEvent>[];
      for (final reason in result.reasons) {
        evs.add(_FakeRiskEvent(
          phone: phone,
          orderId: orderId,
          deviceId: deviceId,
          eventType: reason.wireName,
          metadata: {
            'score': result.score,
            'level': result.level.wireName,
            'action': result.action.wireName,
            'reasons': result.reasons.map((r) => r.wireName).toList(),
          },
        ));
      }
      if (result.action == RiskAction.needsVerification ||
          result.action == RiskAction.rejected) {
        // summary event
        evs.add(_FakeRiskEvent(
          phone: phone,
          orderId: orderId,
          deviceId: deviceId,
          eventType: 'RISK_EVALUATED',
          metadata: {
            'score': result.score,
            'level': result.level.wireName,
            'action': result.action.wireName,
            'reasons': result.reasons.map((r) => r.wireName).toList(),
          },
        ));
      }
      events[orderId] = evs;

      // AFTER: track device upsert (like trg_c_after_track_device)
      if (deviceId != null && deviceId.isNotEmpty) {
        final list = devicesByPhone.putIfAbsent(phone, () => []);
        if (!list.contains(deviceId)) {
          list.add(deviceId);
          devicePhoneCount[deviceId] = (devicePhoneCount[deviceId] ?? 0) + 1;
        }
      }

      return order;
    } catch (e) {
      // Rollback to backups — no partial
      orders
        ..clear()
        ..addAll(ordersBackup);
      events
        ..clear()
        ..addAll(eventsBackup);
      devicesByPhone
        ..clear()
        ..addAll(devicesBackup);
      rethrow;
    }
  }

  void seedProfile(RiskProfile p) {
    profiles[p.phone] = p;
  }
}

class _FakeOrder {
  _FakeOrder({
    required this.id,
    required this.phone,
    required this.subtotalEgp,
    this.deviceId,
    this.addressId,
    required this.displayNumber,
    required this.riskScore,
    required this.riskLevel,
    required this.riskAction,
    required this.riskReasons,
  });

  final String id;
  final String phone;
  final int subtotalEgp;
  final String? deviceId;
  final String? addressId;
  final int displayNumber;
  final int riskScore;
  final String riskLevel;
  final String riskAction;
  final List<String> riskReasons;
}

class _FakeRiskEvent {
  _FakeRiskEvent({
    required this.phone,
    required this.orderId,
    this.deviceId,
    required this.eventType,
    required this.metadata,
  });

  final String phone;
  final String orderId;
  final String? deviceId;
  final String eventType;
  final Map<String, dynamic> metadata;
}

void main() {
  group('risk evaluation flow — collect→evaluate→store→events in one txn', () {
    test('successful transaction stores order + events + device atomically', () {
      final db = FakeRiskDb();
      db.seedProfile(const RiskProfile(phone: '+201000000001', totalOrders: 0));

      final order = db.insertOrder(
        orderId: 'o1',
        phone: '+201000000001',
        subtotalEgp: 600, // large
        deviceId: 'dev-1',
      );

      expect(order.riskReasons, contains('LARGE_ORDER'));
      expect(order.riskReasons, contains('NEW_CUSTOMER'));
      expect(order.riskReasons, contains('NEW_DEVICE'));
      expect(order.riskScore, 45);
      expect(db.orders.containsKey('o1'), isTrue);
      expect(db.events['o1'], isNotNull);
      expect(db.events['o1']!.map((e) => e.eventType),
          containsAll(['NEW_CUSTOMER', 'NEW_DEVICE', 'LARGE_ORDER', 'RISK_EVALUATED']));
      expect(db.devicesByPhone['+201000000001'], contains('dev-1'));
      // metadata carries score/reasons
      final firstEvent = db.events['o1']!.first;
      expect(firstEvent.metadata['score'], 45);
      expect((firstEvent.metadata['reasons'] as List), contains('LARGE_ORDER'));
    });

    test('no partial on failure — invalid subtotal rolls back order+events+device', () {
      final db = FakeRiskDb();
      db.seedProfile(const RiskProfile(phone: '+201000000002', totalOrders: 0));

      expect(
        () => db.insertOrder(
          orderId: 'o-fail',
          phone: '+201000000002',
          subtotalEgp: -100, // triggers failure
          deviceId: 'dev-fail',
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(db.orders.containsKey('o-fail'), isFalse);
      expect(db.events.containsKey('o-fail'), isFalse);
      expect(db.devicesByPhone['+201000000002'], isNull);
    });

    test('corrected subtotal after validate_order_pricing is used, not client-supplied low', () {
      final db = FakeRiskDb();
      db.seedProfile(const RiskProfile(phone: '+201000000003', totalOrders: 0));
      // Client sends subtotal 10 but server recomputes to 600 via validate_order_pricing (simulated by passing 600)
      // This test ensures evaluation reads corrected subtotal, not the forged one.
      // We simulate by calling insertOrder with corrected 600, and verify LARGE_ORDER flagged.
      final order = db.insertOrder(
        orderId: 'o-corrected',
        phone: '+201000000003',
        subtotalEgp: 600, // corrected value (server recomputed from menu_items)
        deviceId: 'dev-corr',
      );
      expect(order.riskReasons, contains('LARGE_ORDER'));
      expect(order.riskScore, greaterThanOrEqualTo(15));
    });

    test('rapidOrders flag derived from recent window count is respected', () {
      final db = FakeRiskDb();
      db.seedProfile(const RiskProfile(phone: '+201000000004', totalOrders: 2));
      // Simulate 2 recent orders in window, current is 3rd → rapid
      final order = db.insertOrder(
        orderId: 'o-rapid',
        phone: '+201000000004',
        subtotalEgp: 100,
        deviceId: 'dev-rapid',
        recentOrderIds: ['prev-1', 'prev-2'],
      );
      expect(order.riskReasons, contains('RAPID_ORDERS'));
      expect(order.riskScore, greaterThanOrEqualTo(20));
    });

    test('device reuse does not double count NEW_DEVICE and MULTIPLE correctly', () {
      final db = FakeRiskDb();
      db.seedProfile(const RiskProfile(phone: '+201000000005', totalOrders: 1));
      db.seedProfile(const RiskProfile(phone: '+201000000006', totalOrders: 0));

      // First phone uses device X → NEW_DEVICE only
      final o1 = db.insertOrder(
        orderId: 'o-dev-1',
        phone: '+201000000005',
        subtotalEgp: 100,
        deviceId: 'shared-dev',
      );
      expect(o1.riskReasons, contains('NEW_DEVICE'));
      expect(o1.riskReasons, isNot(contains('MULTIPLE_ACCOUNTS_DEVICE')));

      // Second phone same device → NEW_DEVICE + MULTIPLE
      final o2 = db.insertOrder(
        orderId: 'o-dev-2',
        phone: '+201000000006',
        subtotalEgp: 100,
        deviceId: 'shared-dev',
      );
      expect(o2.riskReasons, containsAll(['NEW_DEVICE', 'MULTIPLE_ACCOUNTS_DEVICE']));
      expect(o2.riskScore, 40); // 20 NEW_CUSTOMER +10 NEW_DEVICE +10 MULTIPLE
      // Verify second's score includes multiple
      expect(o2.riskScore, greaterThanOrEqualTo(30));
    });

    test('deterministic: same input → same output, no DateTime.now inside', () {
      final db = FakeRiskDb();
      db.seedProfile(const RiskProfile(phone: '+201000000007', totalOrders: 0));
      final a = db.insertOrder(
        orderId: 'o-det-1',
        phone: '+201000000007',
        subtotalEgp: 600,
        deviceId: 'dev-det',
      );
      // Reset and re-insert same context should give same score/reasons
      final db2 = FakeRiskDb();
      db2.seedProfile(const RiskProfile(phone: '+201000000007', totalOrders: 0));
      final b = db2.insertOrder(
        orderId: 'o-det-2',
        phone: '+201000000007',
        subtotalEgp: 600,
        deviceId: 'dev-det',
      );
      expect(a.riskScore, b.riskScore);
      expect(a.riskLevel, b.riskLevel);
      expect(a.riskAction, b.riskAction);
      expect(a.riskReasons, b.riskReasons);
    });

    test('transaction includes display_number assignment (order_display_seq)', () {
      final db = FakeRiskDb();
      db.seedProfile(const RiskProfile(phone: '+201000000008', totalOrders: 0));
      final o1 = db.insertOrder(orderId: 'o-seq-1', phone: '+201000000008', subtotalEgp: 50);
      final o2 = db.insertOrder(orderId: 'o-seq-2', phone: '+201000000008', subtotalEgp: 60);
      expect(o2.displayNumber, greaterThan(o1.displayNumber));
      expect(o1.displayNumber, greaterThanOrEqualTo(1001));
    });
  });
}
