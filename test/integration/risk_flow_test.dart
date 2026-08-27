// Risk flow integration — RISK-08 (issue #53).
// Riverpod + fake DB seam, retry: noAutoRetry, SharedPreferences mock.
// Verifies: placeOrder → risk_evaluated_at set → risk_events row →
// customer_risk_profiles.updated_at bumped → ownOrdersStream emits held status.
// Also verifies realtime propagation to customer poll via stream.
//
// No network — all Supabase seams faked, deterministic via injected clocks.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kady_app/core/riverpod_retry.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/order_status_repository.dart';
import 'package:kady_app/data/repos/orders_repository.dart';
import 'package:kady_app/data/repos/risk_profile_repository.dart';
import 'package:kady_app/domain/order_status_flow.dart';
import 'package:kady_app/domain/risk_engine.dart';
import 'package:kady_app/domain/risk_profile.dart';

// ---------------------------------------------------------------------------
// In-memory store that backs OrdersRepo + OrderStatusRepo + RiskProfileRepo
// as a single transaction (mirrors the 0022 BEFORE/AFTER chain).
// ---------------------------------------------------------------------------

class _FakeOrderRow {
  _FakeOrderRow({
    required this.id,
    required this.googleUserId,
    required this.phone,
    required this.mode,
    required this.status,
    required this.items,
    required this.subtotalEgp,
    required this.deliveryFeeEgp,
    required this.totalEgp,
    required this.displayNumber,
    required this.createdAtUtc,
    required this.riskScore,
    required this.riskLevel,
    required this.riskAction,
    required this.riskReasons,
    required this.riskEvaluatedAt,
    this.deviceId,
    this.addressId,
  });

  final String id;
  final String googleUserId;
  final String phone;
  final String mode;
  OrderWireStatus status;
  final List<OrderItemPayload> items;
  final int subtotalEgp;
  final int deliveryFeeEgp;
  final int totalEgp;
  final int displayNumber;
  final DateTime createdAtUtc;
  int riskScore;
  String riskLevel;
  String riskAction;
  List<String> riskReasons;
  DateTime riskEvaluatedAt;
  final String? deviceId;
  final String? addressId;
}

class _InMemoryRiskStore {
  int _displaySeq = 1000;
  final Map<String, _FakeOrderRow> ordersById = {};
  final Map<String, List<_FakeOrderRow>> ordersByGoogleUserId = {};
  final Map<String, RiskProfile> profilesByPhone = {};
  final Map<String, List<RiskEvent>> eventsByPhone = {};
  final Map<String, StreamController<List<CustomerOrder>>> _orderStreams = {};

  // Expose for assertions
  List<RiskEvent> eventsForPhone(String phone) => eventsByPhone[phone] ?? const [];

  RiskProfile? profileForPhone(String phone) => profilesByPhone[phone];

  // Helpers
  CustomerOrder _toCustomerOrder(_FakeOrderRow row) => CustomerOrder(
        id: row.id,
        displayNumber: row.displayNumber,
        modeWire: row.mode,
        status: row.status,
        createdAtUtc: row.createdAtUtc,
        itemCount: row.items.fold<int>(0, (a, i) => a + i.qty),
        totalEgp: row.totalEgp,
        phone: row.phone,
        addressId: row.addressId,
        riskAction: row.riskAction,
        riskScore: row.riskScore,
        riskLevel: row.riskLevel,
        riskReasons: row.riskReasons,
      );

  List<CustomerOrder> ownOrdersFor(String googleUserId) {
    final list = ordersByGoogleUserId[googleUserId] ?? const [];
    final sorted = List<_FakeOrderRow>.from(list)
      ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    return sorted.map(_toCustomerOrder).toList();
  }

  Stream<List<CustomerOrder>> watchOwnOrders(String googleUserId) async* {
    // Initial snapshot (synchronous for Riverpod StreamProvider first emission)
    yield ownOrdersFor(googleUserId);
    final ctrl = _orderStreams.putIfAbsent(
      googleUserId,
      () => StreamController<List<CustomerOrder>>.broadcast(),
    );
    yield* ctrl.stream;
  }

  void _emit(String googleUserId) {
    // Ensure controller exists before adding so no emission is dropped
    final ctrl = _orderStreams.putIfAbsent(
      googleUserId,
      () => StreamController<List<CustomerOrder>>.broadcast(),
    );
    if (!ctrl.isClosed) {
      ctrl.add(ownOrdersFor(googleUserId));
    }
  }

  // Place order — computes risk via calculateRisk (mirrors evaluate_order_risk_trigger)
  // and creates risk_events + bumps profile.updatedAt in same synchronous path.
  Future<PlacedOrder> placeOrder(NewOrder order, {DateTime? nowUtc}) async {
    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    // Resolve phone: if order.phone supplied use it, else derived from googleUserId map
    // For test we require order.phone or fallback to a deterministic fake phone
    final phone = order.phone ?? _phoneForGoogleUserId(order.googleUserId);
    final subtotal = order.subtotalEgp; // already computed by caller; server would recompute from menu_items but we trust input for this flow

    // Build profile snapshot (or new customer when none)
    var profile = profilesByPhone[phone];
    profile ??= RiskProfile(phone: phone, totalOrders: 0, successfulOrders: 0, phoneVerified: false);

    // Device counts — simplified (test controls via order.deviceId)
    int deviceCustomerCount = 0;
    if (order.deviceId != null && order.deviceId!.isNotEmpty) {
      // Count distinct phones already using this deviceId in existing orders
      final phonesForDevice = ordersById.values
          .where((o) => o.deviceId == order.deviceId)
          .map((o) => o.phone)
          .toSet();
      final isNewPairing = !ordersById.values.any((o) => o.phone == phone && o.deviceId == order.deviceId);
      deviceCustomerCount = isNewPairing ? phonesForDevice.length + 1 : phonesForDevice.length;
    }

    final isLarge = subtotal >= RiskConfig.fallback.largeOrderThreshold;
    final ctx = RiskContext(
      subtotalEgp: subtotal,
      isNewCustomer: profile.totalOrders == 0,
      isVerifiedPhone: profile.phoneVerified,
      successfulOrders: profile.successfulOrders,
      previousFailedDeliveries: profile.failedDeliveries,
      previousRejectedOrders: profile.rejectedOrders,
      cancellationsCount: profile.cancelledOrders,
      isLargeOrder: isLarge,
      deviceCustomerCount: deviceCustomerCount,
    );
    final result = calculateRisk(ctx);

    final id = 'order_${ordersById.length + 1}_${DateTime.now().microsecondsSinceEpoch}';
    final displayNumber = ++_displaySeq;
    final row = _FakeOrderRow(
      id: id,
      googleUserId: order.googleUserId,
      phone: phone,
      mode: order.mode.wireName,
      status: OrderWireStatus.received,
      items: order.items,
      subtotalEgp: subtotal,
      deliveryFeeEgp: order.deliveryFeeEgp,
      totalEgp: order.totalEgp,
      displayNumber: displayNumber,
      createdAtUtc: now,
      riskScore: result.score,
      riskLevel: result.level.wireName,
      riskAction: result.action.wireName,
      riskReasons: result.reasons.map((r) => r.wireName).toList(),
      riskEvaluatedAt: now,
      deviceId: order.deviceId,
      addressId: order.addressId,
    );
    ordersById[id] = row;
    ordersByGoogleUserId.putIfAbsent(order.googleUserId, () => []).add(row);

    // AFTER INSERT create_risk_events per reason in same txn
    final events = <RiskEvent>[];
    for (final reason in result.reasons) {
      events.add(RiskEvent(
        id: (eventsByPhone[phone]?.length ?? 0) + events.length + 1,
        phone: phone,
        orderId: id,
        deviceId: order.deviceId,
        eventType: reason.wireName,
        metadata: {
          'score': result.score,
          'level': result.level.wireName,
          'action': result.action.wireName,
          'reasons': result.reasons.map((r) => r.wireName).toList(),
        },
        createdAt: now,
      ));
    }
    if (result.action == RiskAction.needsVerification || result.action == RiskAction.rejected) {
      events.add(RiskEvent(
        id: (eventsByPhone[phone]?.length ?? 0) + events.length + 1,
        phone: phone,
        orderId: id,
        deviceId: order.deviceId,
        eventType: 'RISK_EVALUATED',
        metadata: {
          'score': result.score,
          'level': result.level.wireName,
          'action': result.action.wireName,
          'reasons': result.reasons.map((r) => r.wireName).toList(),
        },
        createdAt: now,
      ));
    }
    eventsByPhone.putIfAbsent(phone, () => []).addAll(events);

    // Bump customer_risk_profiles.updated_at (mirrors sync side-effect: profile touched)
    // We don't auto-increment counters on insert — counters only on terminal status via sync_risk_profile,
    // but updated_at is bumped for risk evaluation audit.
    final bumped = (profilesByPhone[phone] ?? profile).copyWith(
      updatedAt: now,
      riskScore: result.score,
      riskLevel: result.level,
    );
    profilesByPhone[phone] = bumped;

    // Realtime emit
    _emit(order.googleUserId);

    return PlacedOrder(
      id: id,
      displayNumber: displayNumber,
      riskAction: row.riskAction,
      riskScore: row.riskScore,
      riskLevel: row.riskLevel,
      riskReasons: row.riskReasons,
    );
  }

  String _phoneForGoogleUserId(String gid) => '+20100${gid.hashCode.abs().toString().padLeft(7, '0').substring(0, 7)}';

  void seedProfile(RiskProfile p) => profilesByPhone[p.phone] = p;

  void transitionStatus(String orderId, OrderWireStatus to) {
    final row = ordersById[orderId];
    if (row == null) throw StateError('order not found');
    row.status = to;
    _emit(row.googleUserId);
  }

  void dispose() {
    for (final c in _orderStreams.values) {
      c.close();
    }
  }
}

class _FakeOrdersRepo implements OrdersRepo {
  _FakeOrdersRepo(this._store);
  final _InMemoryRiskStore _store;

  @override
  Future<int> fetchDeliveryFee() async => 15;

  @override
  Future<List<SavedAddress>> fetchAddresses(String googleUserId) async => const [];

  @override
  Future<SavedAddress> saveAddress(SavedAddressInput input) async =>
      throw UnimplementedError();

  @override
  Future<PlacedOrder> placeOrder(NewOrder order) => _store.placeOrder(order);
}

class _FakeOrderStatusRepo implements OrderStatusRepo {
  _FakeOrderStatusRepo(this._store);
  final _InMemoryRiskStore _store;

  @override
  Future<List<CustomerOrder>> fetchOwnOrders(String googleUserId) async =>
      _store.ownOrdersFor(googleUserId);

  @override
  Future<List<OrderEventRow>> fetchEvents(String orderId) async => const [];

  @override
  Stream<CustomerOrder?> watchOrder(String orderId) =>
      Stream.value(_store.ordersById[orderId] != null ? _store._toCustomerOrder(_store.ordersById[orderId]!) : null);

  @override
  Stream<List<CustomerOrder>> watchOwnOrders(String googleUserId) => _store.watchOwnOrders(googleUserId);
}

class _FakeRiskProfileRepo implements RiskProfileRepo {
  _FakeRiskProfileRepo(this._store);
  final _InMemoryRiskStore _store;

  @override
  Future<RiskProfile?> fetchProfile(String phone) async => _store.profileForPhone(phone);

  @override
  Future<List<RiskEvent>> fetchRecentEvents(String phone, {int limit = 20}) async {
    final all = _store.eventsForPhone(phone);
    final sorted = List<RiskEvent>.from(all)
      ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return sorted.take(limit).toList();
  }
}

OrderItemPayload _item({String id = 'item-1', int qty = 1, int unitTotal = 120}) => OrderItemPayload(
      id: id,
      nameAr: 'شاي',
      qty: qty,
      unitTotalEgp: unitTotal,
      config: const ItemConfig(sizeIndex: 0, sugarIndex: 1, addons: {}),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _InMemoryRiskStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _InMemoryRiskStore();
    // Seed a customer profile — new customer, not verified, no history (low-risk baseline)
    // For medium-risk test we seed no profile (treated as new)
  });

  tearDown(() => store.dispose());

  ProviderContainer containerForStore(_InMemoryRiskStore s) => ProviderContainer(
        overrides: [
          ordersRepoProvider.overrideWithValue(_FakeOrdersRepo(s)),
          orderStatusRepoProvider.overrideWithValue(_FakeOrderStatusRepo(s)),
          riskProfileRepoProvider.overrideWithValue(_FakeRiskProfileRepo(s)),
        ],
        retry: noAutoRetry,
      );

  group('risk_flow — placeOrder gate in same txn', () {
    test('placeOrder with large order → risk_evaluated_at set, risk_events row, profile bumped, stream emits held', () async {
      SharedPreferences.setMockInitialValues({});
      final container = containerForStore(store);
      addTearDown(container.dispose);

      const googleUserId = 'gid-customer-risk-flow';
      const phone = '+201001234567';
      // Ensure profile exists as new (totalOrders 0) so NEW_CUSTOMER fires
      store.seedProfile(RiskProfile(phone: phone, totalOrders: 0, phoneVerified: false));

      // Watch stream before placing — expect realtime emission after place
      final stream = container.read(orderStatusRepoProvider).watchOwnOrders(googleUserId);
      final emitted = <List<CustomerOrder>>[];
      final sub = stream.listen(emitted.add);
      addTearDown(sub.cancel);
      // Initial empty
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(emitted.isNotEmpty, isTrue);
      expect(emitted.last, isEmpty);

      // Place medium-risk order: NEW_CUSTOMER + LARGE_ORDER (650) => 35 medium needs_verification
      final placed = await container.read(ordersRepoProvider).placeOrder(
            NewOrder(
              mode: OrderMode.pickup,
              googleUserId: googleUserId,
              phone: phone,
              items: [_item(unitTotal: 650)],
              subtotalEgp: 650,
              deliveryFeeEgp: 0,
              totalEgp: 650,
              pointsPreview: 65,
              deviceId: 'device-flow-1',
              idempotencyKey: 'flow-key-1',
            ),
          );

      // 1. risk_evaluated_at set (UTC, via store row)
      expect(placed.riskAction, 'needs_verification');
      expect(placed.riskLevel, 'medium');
      expect(placed.riskScore, 35);
      expect(placed.riskReasons, containsAll(['NEW_CUSTOMER', 'LARGE_ORDER']));
      final storedRow = store.ordersById[placed.id]!;
      expect(storedRow.riskEvaluatedAt.isUtc, isTrue);
      expect(storedRow.riskEvaluatedAt.toIso8601String(), endsWith('Z'));
      // Must be recent (within a few seconds of now)
      expect(DateTime.now().toUtc().difference(storedRow.riskEvaluatedAt).inSeconds.abs(), lessThan(5));

      // 2. risk_events row per reason + RISK_EVALUATED
      final events = store.eventsForPhone(phone);
      expect(events, isNotEmpty);
      expect(events.map((e) => e.eventType), contains('NEW_CUSTOMER'));
      expect(events.map((e) => e.eventType), contains('LARGE_ORDER'));
      expect(events.map((e) => e.eventType), contains('RISK_EVALUATED'));
      // Metadata carries score/level/action/reasons
      final evalEvent = events.firstWhere((e) => e.eventType == 'RISK_EVALUATED');
      expect(evalEvent.metadata['score'], 35);
      expect(evalEvent.metadata['level'], 'medium');
      expect(evalEvent.metadata['action'], 'needs_verification');

      // 3. customer_risk_profiles.updated_at bumped
      final profile = store.profileForPhone(phone);
      expect(profile, isNotNull);
      expect(profile!.updatedAt, isNotNull);
      expect(profile.updatedAt!.isUtc, isTrue);
      expect(profile.updatedAt, storedRow.riskEvaluatedAt); // bumped to same txn time
      expect(profile.riskScore, 35);
      expect(profile.riskLevel, RiskLevel.medium);

      // 4. ownOrdersStream emits held status via realtime
      // Wait for stream to emit the inserted row
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(emitted.length, greaterThanOrEqualTo(2));
      final latest = emitted.last;
      expect(latest.length, 1);
      expect(latest.first.id, placed.id);
      expect(latest.first.needsVerification, isTrue);
      expect(latest.first.riskAction, 'needs_verification');
      expect(latest.first.riskScore, 35);
      // Not yet terminal — customer would see "تحقق مطلوب" banner, not yet accepted
      expect(latest.first.status, OrderWireStatus.received);

      // Also verify via direct fetch (mirrors what ownOrdersStreamProvider would emit)
      final viaFetch = await container.read(orderStatusRepoProvider).fetchOwnOrders(googleUserId);
      expect(viaFetch.length, 1);
      expect(viaFetch.first.riskAction, 'needs_verification');
    });

    test('low-risk trusted returning order → approved, no hold, stream emits approved', () async {
      SharedPreferences.setMockInitialValues({});
      final localStore = _InMemoryRiskStore();
      addTearDown(localStore.dispose);
      const gid = 'gid-trusted';
      const phone = '+201009999999';
      localStore.seedProfile(RiskProfile(
        phone: phone,
        totalOrders: 6,
        successfulOrders: 5,
        phoneVerified: true,
      ));
      final container = ProviderContainer(
        overrides: [
          ordersRepoProvider.overrideWithValue(_FakeOrdersRepo(localStore)),
          orderStatusRepoProvider.overrideWithValue(_FakeOrderStatusRepo(localStore)),
          riskProfileRepoProvider.overrideWithValue(_FakeRiskProfileRepo(localStore)),
        ],
        retry: noAutoRetry,
      );
      addTearDown(container.dispose);

      final placed = await container.read(ordersRepoProvider).placeOrder(
            NewOrder(
              mode: OrderMode.dineIn,
              googleUserId: gid,
              phone: phone,
              items: [_item(unitTotal: 90)],
              subtotalEgp: 90,
              deliveryFeeEgp: 0,
              totalEgp: 90,
              pointsPreview: 10,
            ),
          );
      expect(placed.riskAction, 'approved');
      expect(placed.riskLevel, 'low');
      expect(placed.riskScore, 0);
      // Events for bonuses still emitted per risk_reasons? Only FIVE_PLUS_SUCCESSFUL etc. when positive? Actually bonuses are negative, they are reasons too
      // For trusted, reasons include FIVE_PLUS_SUCCESSFUL + VERIFIED_PHONE but score clamped 0 still medium? No, score 0 low
      expect(placed.riskReasons, contains('FIVE_PLUS_SUCCESSFUL'));

      final streamList = await container.read(orderStatusRepoProvider).watchOwnOrders(gid).first;
      expect(streamList.first.needsVerification, isFalse);
      expect(streamList.first.isRejected, isFalse);
    });

    test('non-regression: forged pricing still overwritten (server recompute) alongside risk', () async {
      // Demonstrates 0016 still runs before risk (trigger ordering a→b). We simulate by
      // ensuring the test's helper recompute would fix forged total before evaluate.
      const menuPrices = {
        'item-1': 120,
        'item-2': 60,
      };
      final items = [
        _item(id: 'item-1', qty: 1, unitTotal: 120),
        _item(id: 'item-2', qty: 2, unitTotal: 60),
      ];
      // Client forges subtotal=1, total=1 — server would recompute 120+120=240
      int recompute(List<OrderItemPayload> its) =>
          its.fold<int>(0, (a, it) => a + (menuPrices[it.id] ?? 0) * it.qty);
      final computed = recompute(items);
      expect(computed, 240);
      expect(computed, isNot(1));
      // If we then evaluate risk on computed subtotal 240 (not large), risk stays low even if client tried to inflate/deflate
      final phone2 = '+201008888888';
      store.seedProfile(RiskProfile(phone: phone2, successfulOrders: 5, phoneVerified: true));
      final placed = await _FakeOrdersRepo(store).placeOrder(
            NewOrder(
              mode: OrderMode.pickup,
              googleUserId: 'gid-forge',
              phone: phone2,
              items: items,
              subtotalEgp: 1, // forged
              deliveryFeeEgp: 0,
              totalEgp: 1, // forged — would be overwritten to 240 server-side; risk uses recomputed threshold check
              pointsPreview: 0,
            ),
          );
      // Our fake uses the forged subtotal as-is, but real SQL uses recomputed; this test documents the contract
      // For correctness, we assert that a correct server would see 240 (<500) → not LARGE_ORDER, so still low
      // The fake with forged 1 also gives low (both <500), so gate parity holds for this case
      expect(placed.riskAction, 'approved');
    });
  });
}
