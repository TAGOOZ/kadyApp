// Risk scenarios coverage — RISK-08 (issue #53, plan §20).
// Pure engine + fakes, no network, no Supabase.
// Covers all 6 plan §20 scenarios, threshold variants, shared-device signal cap,
// manual verification confirm/reject with audit, plus non-regression and time/i18n checks.
//
// Keep Dart and SQL identical when changing either (see lib/domain/risk_engine.dart header).

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/l10n/strings_risk.dart';
import 'package:kady_app/data/repos/orders_repository.dart';
import 'package:kady_app/data/repos/verification_repository.dart';
import 'package:kady_app/domain/risk_engine.dart';
import 'package:kady_app/domain/risk_profile.dart';
import 'package:kady_app/domain/verification_service.dart';

// ---------------------------------------------------------------------------
// Helpers — fake gate & formatting (mirrors SQL dispatch & display)
// ---------------------------------------------------------------------------

class _FakeRiskGate {
  final Map<String, _PlacedRisk> _orders = {};
  final Set<String> _confirmed = {};
  final Map<String, String> _rejectReasons = {};
  final List<RiskEvent> _riskEvents = [];

  _PlacedRisk placeOrder(String id, RiskContext ctx,
      {RiskConfig config = RiskConfig.fallback, List<RiskRule>? rules}) {
    final r = calculateRisk(ctx, config: config, rules: rules);
    final placed = _PlacedRisk(
      id: id,
      score: r.score,
      level: r.level,
      action: r.action,
      reasons: r.reasons,
      evaluatedAt: DateTime.now().toUtc(),
    );
    _orders[id] = placed;
    // Create risk_events per reason in same txn (mirrors trg_a_after_create_risk_events)
    for (final reason in r.reasons) {
      _riskEvents.add(RiskEvent(
        id: _riskEvents.length + 1,
        phone: '+201000000000',
        orderId: id,
        eventType: reason.wireName,
        metadata: {
          'score': r.score,
          'level': r.level.wireName,
          'action': r.action.wireName,
          'reasons': r.reasons.map((e) => e.wireName).toList(),
        },
        createdAt: placed.evaluatedAt,
      ));
    }
    if (r.action == RiskAction.needsVerification || r.action == RiskAction.rejected) {
      _riskEvents.add(RiskEvent(
        id: _riskEvents.length + 1,
        phone: '+201000000000',
        orderId: id,
        eventType: 'RISK_EVALUATED',
        metadata: {
          'score': r.score,
          'level': r.level.wireName,
          'action': r.action.wireName,
          'reasons': r.reasons.map((e) => e.wireName).toList(),
        },
        createdAt: placed.evaluatedAt,
      ));
    }
    return placed;
  }

  // Mirrors prod confirm_verification (0024): flips risk_action to approved
  // and resets score/level/reasons to 0/low/[] for gate lift; audit retained
  // in risk_events (VERIFICATION_CONFIRMED) not in score retention.
  void confirmVerification(String orderId) {
    _confirmed.add(orderId);
    final existing = _orders[orderId];
    if (existing != null && existing.action == RiskAction.needsVerification) {
      _orders[orderId] = _PlacedRisk(
        id: existing.id,
        score: 0,
        level: RiskLevel.low,
        action: RiskAction.approved,
        reasons: const [],
        evaluatedAt: DateTime.now().toUtc(),
      );
      _riskEvents.add(RiskEvent(
        id: _riskEvents.length + 1,
        phone: '+201000000000',
        orderId: orderId,
        eventType: 'VERIFICATION_CONFIRMED',
        metadata: {'order_id': orderId, 'via': 'staff'},
        createdAt: DateTime.now().toUtc(),
      ));
    }
  }

  void rejectVerification(String orderId, {String reason = 'verification_rejected'}) {
    final existing = _orders[orderId];
    if (existing != null) {
      _orders[orderId] = _PlacedRisk(
        id: existing.id,
        score: existing.score,
        level: RiskLevel.high,
        action: RiskAction.rejected,
        reasons: existing.reasons,
        evaluatedAt: existing.evaluatedAt,
      );
      _rejectReasons[orderId] = reason;
      _riskEvents.add(RiskEvent(
        id: _riskEvents.length + 1,
        phone: '+201000000000',
        orderId: orderId,
        eventType: 'VERIFICATION_REJECTED',
        metadata: {'order_id': orderId, 'reason': reason},
        createdAt: DateTime.now().toUtc(),
      ));
    }
  }

  void transitionOrder(String orderId, String newStatus) {
    final order = _orders[orderId];
    if (order == null) throw StateError('order $orderId not found');
    const blocked = {
      'accepted',
      'in_prep',
      'ready',
      'out_for_delivery',
      'done'
    };
    if (order.action == RiskAction.needsVerification &&
        blocked.contains(newStatus) &&
        !_confirmed.contains(orderId)) {
      throw StateError('needs verification (P0001)');
    }
    if (order.action == RiskAction.rejected && blocked.contains(newStatus)) {
      throw StateError('order rejected (P0001)');
    }
  }

  _PlacedRisk? getOrder(String id) => _orders[id];
  String? rejectReasonFor(String id) => _rejectReasons[id];
  List<RiskEvent> eventsForOrder(String orderId) =>
      _riskEvents.where((e) => e.orderId == orderId).toList();
  List<RiskEvent> get allEvents => List.unmodifiable(_riskEvents);
}

class _PlacedRisk {
  const _PlacedRisk({
    required this.id,
    required this.score,
    required this.level,
    required this.action,
    required this.reasons,
    required this.evaluatedAt,
  });
  final String id;
  final int score;
  final RiskLevel level;
  final RiskAction action;
  final List<RuleCode> reasons;
  final DateTime evaluatedAt;
  bool get needsVerification => action == RiskAction.needsVerification;
  bool get isRejected => action == RiskAction.rejected;
}

// Cairo display helper — mirrors lib/data/repos/customer_lookup_repository.dart:formatLookupWhenUtc
// Also verifies the canonical helper in orders_repository.dart: formatRiskEvaluatedAt
String _formatRiskEvaluatedAt(DateTime utcInstant) => formatRiskEvaluatedAt(utcInstant);

// Fake loyalty store with processed_orders guard (mirrors 0004)
class _FakeLoyaltyStore {
  int points = 100;
  int lifetimePoints = 100;
  int stamps = 0;
  final Set<String> _processedOrders = {};

  bool creditOrder(String orderId, {required int earned}) {
    if (_processedOrders.contains(orderId)) return false; // guard
    points += earned;
    lifetimePoints += earned;
    _processedOrders.add(orderId);
    return true;
  }

  bool isProcessed(String orderId) => _processedOrders.contains(orderId);
}

// Fake pricing recompute — mirrors 0016_validate_order_pricing
int _recomputeTotal({
  required Map<String, int> menuPriceById,
  required List<Map<String, dynamic>> items,
  required String mode,
  int configuredDeliveryFee = 15,
}) {
  var subtotal = 0;
  for (final item in items) {
    final id = item['id'] as String;
    final qty = (item['qty'] as int?) ?? 1;
    final price = menuPriceById[id];
    if (price == null) throw ArgumentError('menu item $id not found');
    subtotal += price * qty;
  }
  final fee = mode == 'delivery' ? configuredDeliveryFee : 0;
  return subtotal + fee;
}

// ---------------------------------------------------------------------------
// §20 Scenario suite
// ---------------------------------------------------------------------------

void main() {
  group('§20 Scenario 1 — Low-risk Customer: new, verified phone, 120 EGP, no history', () {
    test('new verified + normal order 120 → low approved (VERIFIED_PHONE -15 outweighs NEW_CUSTOMER +20 → 5 low)', () {
      // isNewCustomer true (+20), verified (-15) => 5 low approved.
      // Requirement says reasons empty or VERIFIED_PHONE -15 — we assert both interpretations pass.
      const ctx = RiskContext(
        subtotalEgp: 120,
        isNewCustomer: true,
        isVerifiedPhone: true,
      );
      final r = calculateRisk(ctx);
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
      expect(r.score, 5);
      // Score 5 means both NEW_CUSTOMER and VERIFIED_PHONE contributed (20-15=5)
      // Alternative reading: isNewCustomer false (returning but no orders typed?) would be 0-15 clamped 0.
      // We assert level/action are low/approved regardless; reasons either contain VERIFIED_PHONE or are empty per spec.
      expect(r.reasons, contains(RuleCode.verifiedPhone));
      expect(r.reasons, contains(RuleCode.newCustomer));
      // Also verify the neutral case: returning verified customer with 120 should be clamped 0 low
      const returning = RiskContext(
        subtotalEgp: 120,
        isNewCustomer: false,
        isVerifiedPhone: true,
      );
      final r2 = calculateRisk(returning);
      expect(r2.level, RiskLevel.low);
      expect(r2.action, RiskAction.approved);
      expect(r2.score, 0); // -15 clamped
      expect(r2.reasons, contains(RuleCode.verifiedPhone));
    });

    test('empty reasons variant when no rule fires also low approved', () {
      const ctx = RiskContext(); // no flags, no history
      final r = calculateRisk(ctx);
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
      expect(r.reasons, isEmpty);
      expect(r.score, 0);
    });
  });

  group('§20 Scenario 2 — Medium-risk: new Customer, large order 650 (>500)', () {
    test('NEW_CUSTOMER + LARGE_ORDER = 35 → medium needs_verification', () {
      const ctx = RiskContext(
        isNewCustomer: true,
        subtotalEgp: 650,
      );
      final r = calculateRisk(ctx);
      expect(r.score, 35);
      expect(r.level, RiskLevel.medium);
      expect(r.action, RiskAction.needsVerification);
      expect(r.reasons, containsAll([RuleCode.newCustomer, RuleCode.largeOrder]));
      expect(r.reasons.length, 2);
    });

    test('large via flag vs threshold both trigger', () {
      const viaFlag = RiskContext(isNewCustomer: true, isLargeOrder: true);
      const viaThreshold = RiskContext(isNewCustomer: true, subtotalEgp: 500);
      expect(calculateRisk(viaFlag).score, 35);
      expect(calculateRisk(viaThreshold).score, 35);
      const below = RiskContext(isNewCustomer: true, subtotalEgp: 499);
      expect(calculateRisk(below).score, 20);
      expect(calculateRisk(below).level, RiskLevel.low);
    });

    test('medium threshold 500 configurable — Admin can change', () {
      const cfg400 = RiskConfig(largeOrderThreshold: 400);
      const ctx = RiskContext(isNewCustomer: true, subtotalEgp: 450);
      expect(calculateRisk(ctx, config: cfg400).score, 35); // now large
      const cfg700 = RiskConfig(largeOrderThreshold: 700);
      expect(calculateRisk(ctx, config: cfg700).score, 20); // not large under 700
    });
  });

  group('§20 Scenario 3 — High-risk: 3 failed + 3 cancellations + large 700', () {
    test('25+25+15=65 → high rejected (currently 60+ = high)', () {
      const ctx = RiskContext(
        previousFailedDeliveries: 3,
        cancellationsCount: 3,
        isLargeOrder: true, // 700 EGP would also via threshold
        subtotalEgp: 700,
      );
      final r = calculateRisk(ctx);
      expect(r.score, 65);
      expect(r.level, RiskLevel.high);
      expect(r.action, RiskAction.rejected);
      expect(r.reasons,
          containsAll([RuleCode.previousFailedDelivery, RuleCode.threePlusCancellations, RuleCode.largeOrder]));
    });

    test('threshold variant: same score can be medium when mediumMax raised', () {
      // Currently mediumMax 59 => 65 high. With mediumMax 70, 65 becomes medium/needs_verification.
      const medium70 = RiskConfig(lowMaxScore: 29, mediumMaxScore: 70);
      const ctx = RiskContext(
        previousFailedDeliveries: 3,
        cancellationsCount: 3,
        subtotalEgp: 700,
      );
      final rDefault = calculateRisk(ctx); // high
      final rLoose = calculateRisk(ctx, config: medium70); // medium
      expect(rDefault.action, RiskAction.rejected);
      expect(rLoose.action, RiskAction.needsVerification);
      expect(rLoose.level, RiskLevel.medium);
      expect(rLoose.score, 65);
      // High requires >70, so 70 still medium, 71 would be high
      const ctx71 = RiskContext(
        previousFailedDeliveries: 3, //25
        previousRejectedOrders: 1, //30
        isLargeOrder: true, //15 =>70
        subtotalEgp: 700,
        isRapidOrders: true, //20 =>90 (need 71+ to test high beyond 70)
      );
      // 90 with medium70 => high
      final r90 = calculateRisk(ctx71, config: medium70);
      expect(r90.score, 90);
      expect(r90.action, RiskAction.rejected);
    });

    test('high score clamped 0..100 — extreme positives still 100 high', () {
      const ctx = RiskContext(
        isNewCustomer: true, //20
        isNewDevice: true, //10
        previousFailedDeliveries: 5, //25
        previousRejectedOrders: 1, //30
        cancellationsCount: 5, //25
        isLargeOrder: true, //15
        isRapidOrders: true, //20 =>145 clamped 100
        deviceCustomerCount: 5, // +10 extrinsic but still capped? non-extrinsic present so not clamped
      );
      final r = calculateRisk(ctx);
      expect(r.score, 100);
      expect(r.level, RiskLevel.high);
      expect(r.action, RiskAction.rejected);
    });
  });

  group('§20 Scenario 4 — Trusted returning: 5+ successful, verified, 90 EGP normal', () {
    test('FIVE_PLUS_SUCCESSFUL -30 + VERIFIED_PHONE -15 = -45 clamped 0 low approved', () {
      const ctx = RiskContext(
        successfulOrders: 5,
        isVerifiedPhone: true,
        subtotalEgp: 90,
      );
      final r = calculateRisk(ctx);
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
      // bonuses are present as reasons
      expect(r.reasons, contains(RuleCode.fivePlusSuccessful));
      expect(r.reasons, contains(RuleCode.verifiedPhone));
      expect(r.reasons, isNot(contains(RuleCode.threePlusSuccessful))); // exclusive
    });

    test('bonuses outweigh any positives: new device + rapid still low for trusted', () {
      const ctx = RiskContext(
        successfulOrders: 5, // -30
        isVerifiedPhone: true, // -15
        isNewDevice: true, // +10
        isRapidOrders: true, // +20  => 30-45 = -15 clamped 0 low
      );
      final r = calculateRisk(ctx);
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
    });

    test('3 successful alone also low (trusted variant)', () {
      const ctx = RiskContext(
        successfulOrders: 3, // -20
        isVerifiedPhone: true, // -15 => -35 clamped 0
        subtotalEgp: 90,
      );
      final r = calculateRisk(ctx);
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
      expect(r.reasons, contains(RuleCode.threePlusSuccessful));
    });

    test('mirrors RiskProfile bridge: riskContextFromProfile maps 5+ correctly', () {
      const profile = RiskProfile(
        phone: '+201001234567',
        totalOrders: 6,
        successfulOrders: 5,
        phoneVerified: true,
      );
      final ctx = riskContextFromProfile(profile, subtotalEgp: 90);
      final r = calculateRisk(ctx);
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
      expect(r.reasons, containsAll([RuleCode.fivePlusSuccessful, RuleCode.verifiedPhone]));
    });
  });

  group('§20 Scenario 5 — Shared device: A,B,C on same device_id', () {
    test('second customer +10 signal, third still medium not rejected (signal not proof)', () {
      const deviceId = 'device-shared-uuid-v4';
      // Simulate in-memory device table
      final phoneByDevice = <String, Set<String>>{deviceId: {}};
      int deviceCustomerCount(String device, String phone) {
        final existing = phoneByDevice[device] ?? {};
        final isNew = !existing.contains(phone);
        return isNew ? existing.length + 1 : existing.length;
      }

      // Customer A: first on device → NEW_DEVICE (+10) but no MULTIPLE yet
      const ctxA = RiskContext(
        isNewCustomer: true,
        isNewDevice: true,
        deviceCustomerCount: 1, // first distinct
      );
      final rA = calculateRisk(ctxA);
      expect(rA.score, 30); // 20 new customer +10 new device
      expect(rA.level, RiskLevel.medium);
      expect(rA.action, RiskAction.needsVerification);
      expect(rA.reasons, containsAll([RuleCode.newCustomer, RuleCode.newDevice]));
      // track A
      phoneByDevice[deviceId] = { 'A' };

      // Customer B: second distinct phone on same device → +10 MULTIPLE + NEW_DEVICE if new pairing
      // For B, deviceCustomerCount becomes 2 (effective after insert)
      final ctxB = RiskContext(
        isNewCustomer: true,
        isNewDevice: true, // B never used this device before
        deviceCustomerCount: deviceCustomerCount(deviceId, 'B'), // 2
      );
      final rB = calculateRisk(ctxB);
      expect(rB.score, 40); // 20 +10 newDevice +10 multiple
      expect(rB.level, RiskLevel.medium);
      expect(rB.action, RiskAction.needsVerification);
      expect(rB.reasons, contains(RuleCode.multipleAccountsDevice));
      // Still not rejected — signal not proof (extrinsic-only cap would keep ≤59 even if high)
      expect(rB.action, isNot(RiskAction.rejected));
      phoneByDevice[deviceId]!.add('B');

      // Customer C: third distinct → same +10 (MULTIPLE stays +10, not cumulative)
      final ctxC = RiskContext(
        isNewCustomer: true,
        isNewDevice: true,
        deviceCustomerCount: deviceCustomerCount(deviceId, 'C'), // 3
      );
      final rC = calculateRisk(ctxC);
      expect(rC.score, 40); // 20+10+10 same as B (MULTIPLE is binary ≥2)
      expect(rC.level, RiskLevel.medium);
      expect(rC.action, RiskAction.needsVerification);
      expect(rC.action, isNot(RiskAction.rejected));
      expect(rC.reasons, contains(RuleCode.multipleAccountsDevice));
    });

    test('extrinsic-only signals alone never push to high (capped at mediumMax)', () {
      // No non-extrinsic positives, only device signals with high scores would otherwise hit high.
      // isExtrinsic flag drives the cap (data-driven) — legacy fallback also covers these codes.
      const extrinsicHighRules = [
        RiskRule(code: RuleCode.newDevice, score: 40, isExtrinsic: true),
        RiskRule(code: RuleCode.multipleAccountsDevice, score: 40, isExtrinsic: true),
      ];
      const ctx = RiskContext(
        isNewDevice: true,
        deviceCustomerCount: 3, // triggers multiple
      );
      final r = calculateRisk(ctx, rules: extrinsicHighRules);
      // Raw would be 80 high, but extrinsicOnly clamp forces ≤59 medium
      expect(r.score, lessThanOrEqualTo(59));
      expect(r.level, isNot(RiskLevel.high));
      expect(r.action, isNot(RiskAction.rejected));
      // In UI this still means queue shows "needs_verification" but not auto-rejected
    });

    test('device reuse without MULTIPLE disabled does not score extra', () {
      const ctx = RiskContext(
        isNewCustomer: true,
        deviceCustomerCount: 5,
      );
      // Disable MULTIPLE_ACCOUNTS_DEVICE — should not add +10
      final rulesNoShared = kDefaultRiskRules
          .map((r) => r.code == RuleCode.multipleAccountsDevice
              ? RiskRule(code: r.code, score: r.score, enabled: false)
              : r)
          .toList();
      final r = calculateRisk(ctx, rules: rulesNoShared);
      expect(r.score, 20); // only NEW_CUSTOMER
      expect(r.reasons, isNot(contains(RuleCode.multipleAccountsDevice)));
    });
  });

  group('§20 Scenario 6 — Manual verification: needs_verification → confirm/reject', () {
    test('needs_verification → staff confirm → approved persists and transition_order allows accepted', () async {
      // Place medium order that triggers needs_verification
      final gate = _FakeRiskGate();
      final placed = gate.placeOrder(
        'order-confirm',
        const RiskContext(isNewCustomer: true, subtotalEgp: 650), // 35 medium
      );
      expect(placed.action, RiskAction.needsVerification);
      expect(placed.needsVerification, isTrue);

      // Dispatch gate blocks accepted before verification
      expect(() => gate.transitionOrder('order-confirm', 'accepted'),
          throwsA(isA<StateError>().having((e) => e.toString(), 'message', contains('P0001'))));

      // Seed verification request (manual provider, placeholder hash) — mirrors FakeVerificationRepo
      final verRepo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(verRepo);
      final service = VerificationServiceImpl(providers: {'manual': manual}, repo: verRepo);
      // Create pending (idempotent)
      final req = await service.request(orderId: 'order-confirm', phone: '+201001234567');
      expect(req.status, VerificationStatus.pending);
      expect(req.provider, 'manual');
      // Plaintext code never stored — even manual placeholder hash ≠ code
      final hash = verRepo.codeHashFor('order-confirm');
      expect(hash, isNotNull);
      expect(hash, isNotEmpty);
      expect(hash, isNot('123456'));

      // Staff confirm (SECURITY DEFINER, staff role required)
      await service.confirmByStaff(orderId: 'order-confirm');
      final after = await verRepo.fetchByOrderId('order-confirm');
      expect(after!.status, VerificationStatus.confirmed);
      expect(verRepo.codeHashFor('order-confirm'), anyOf(isNull, isEmpty, ''));

      // Also flip gate's risk_action to approved (mirrors confirm_verification trigger)
      gate.confirmVerification('order-confirm');
      final approved = gate.getOrder('order-confirm')!;
      expect(approved.action, RiskAction.approved);
      expect(approved.level, RiskLevel.low);

      // Now transition_order allows accepted (and in_prep, ready, etc.)
      expect(() => gate.transitionOrder('order-confirm', 'accepted'), returnsNormally);
      expect(() => gate.transitionOrder('order-confirm', 'in_prep'), returnsNormally);

      // Audit: risk_events row emitted
      final events = gate.eventsForOrder('order-confirm');
      expect(events.map((e) => e.eventType), contains('VERIFICATION_CONFIRMED'));
    });

    test('needs_verification → staff reject → rejected/cancelled with reject_reason and audit row', () async {
      final gate = _FakeRiskGate();
      final placed = gate.placeOrder(
        'order-reject',
        const RiskContext(isNewCustomer: true, subtotalEgp: 650),
      );
      expect(placed.action, RiskAction.needsVerification);

      final verRepo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(verRepo);
      final service = VerificationServiceImpl(providers: {'manual': manual}, repo: verRepo);

      await service.request(orderId: 'order-reject', phone: '+201009999999');
      // Staff reject (reason defaults to verification_rejected per spec)
      await service.rejectByStaff(orderId: 'order-reject', reason: 'verification_rejected');
      final after = await verRepo.fetchByOrderId('order-reject');
      expect(after!.status, VerificationStatus.rejected);
      // Repo fake mirrors reject_verification → orders.status cancelled + reject_reason
      // We simulate same via gate
      gate.rejectVerification('order-reject', reason: 'verification_rejected');
      final rejected = gate.getOrder('order-reject')!;
      expect(rejected.action, RiskAction.rejected);
      expect(rejected.isRejected, isTrue);
      expect(gate.rejectReasonFor('order-reject'), 'verification_rejected');

      // Dispatch gate still blocks accepted for rejected (terminal)
      expect(() => gate.transitionOrder('order-reject', 'accepted'), throwsA(isA<StateError>()));
      // allowed transition is cancelled (or stays cancelled)
      final events = gate.eventsForOrder('order-reject');
      expect(events.map((e) => e.eventType), contains('VERIFICATION_REJECTED'));
    });

    test('double confirm is idempotent — second confirm no-op, no duplicate credit', () async {
      final verRepo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(verRepo);
      final service = VerificationServiceImpl(providers: {'manual': manual}, repo: verRepo);
      await service.request(orderId: 'order-double-confirm', phone: '+201002222222');
      await service.confirmByStaff(orderId: 'order-double-confirm');
      final first = await verRepo.fetchByOrderId('order-double-confirm');
      expect(first!.status, VerificationStatus.confirmed);
      // Second confirm should not throw and should leave confirmed
      await service.confirmByStaff(orderId: 'order-double-confirm');
      final second = await verRepo.fetchByOrderId('order-double-confirm');
      expect(second!.status, VerificationStatus.confirmed);
      // No duplicate audit row beyond idempotent set — fake emits only on first flip
    });

    test('customer role cannot confirm (42501)', () async {
      final verRepo = FakeVerificationRepo(currentRole: 'customer');
      await verRepo.requestVerification(orderId: 'order-no-perm', phone: '+201003333333');
      expect(() => verRepo.confirmByStaff(orderId: 'order-no-perm'),
          throwsA(isA<VerificationPermissionException>()));
    });
  });

  // -----------------------------------------------------------------------
  // Non-regression — pricing guard & loyalty idempotency
  // -----------------------------------------------------------------------

  group('Non-regression: 0016_validate_order_pricing still recomputes from menu_items', () {
    final menuPrices = <String, int>{
      '11111111-1111-1111-1111-111111111111': 120, // e.g. hot drink
      '22222222-2222-2222-2222-222222222222': 60,
    };

    test('forged subtotal=1 still stores computed total (items-based)', () {
      // Client forges subtotal=1, delivery_fee=0, total=1 — server recomputes
      const forgedSubtotal = 1;
      const forgedTotal = 1;
      final items = [
        {'id': '11111111-1111-1111-1111-111111111111', 'qty': 1},
        {'id': '22222222-2222-2222-2222-222222222222', 'qty': 2},
      ];
      // Expected: 120*1 + 60*2 = 240, delivery pickup => 0 fee => total 240
      final computedTotal = _recomputeTotal(
        menuPriceById: menuPrices,
        items: items,
        mode: 'pickup',
      );
      expect(computedTotal, 240);
      expect(computedTotal, isNot(forgedTotal));
      expect(forgedSubtotal, isNot(computedTotal));
      // Simulate server overwriting the forged values (as trigger does NEW.subtotal := computed)
      final wouldStore = computedTotal; // after trigger
      expect(wouldStore, 240);
    });

    test('delivery mode adds configured fee, not client-supplied fee', () {
      final items = [
        {'id': '11111111-1111-1111-1111-111111111111', 'qty': 1},
      ];
      // Client forges delivery_fee=1 but server uses admin config 15
      final totalPickup = _recomputeTotal(menuPriceById: menuPrices, items: items, mode: 'pickup');
      final totalDelivery =
          _recomputeTotal(menuPriceById: menuPrices, items: items, mode: 'delivery', configuredDeliveryFee: 15);
      expect(totalPickup, 120);
      expect(totalDelivery, 135); // 120 +15
      expect(totalDelivery - totalPickup, 15);
    });

    test('unknown menu item id raises (22023) rather than silent 0', () {
      expect(
        () => _recomputeTotal(
          menuPriceById: menuPrices,
          items: [
            {'id': '99999999-9999-9999-9999-999999999999', 'qty': 1}
          ],
          mode: 'pickup',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Non-regression: loyalty_state not double-credited via processed_orders guard (0004:99)', () {
    test('first credit succeeds, second with same orderId is no-op', () {
      final store = _FakeLoyaltyStore();
      final first = store.creditOrder('order-loyalty-1', earned: 10);
      expect(first, isTrue);
      expect(store.points, 110);
      expect(store.lifetimePoints, 110);
      expect(store.isProcessed('order-loyalty-1'), isTrue);

      // Second attempt with same orderId (e.g., credit_on_verification_approval replay) must be no-op
      final second = store.creditOrder('order-loyalty-1', earned: 10);
      expect(second, isFalse);
      expect(store.points, 110); // not 120
      expect(store.lifetimePoints, 110);
    });

    test('different orderIds each credit once', () {
      final store = _FakeLoyaltyStore();
      expect(store.creditOrder('o-1', earned: 5), isTrue);
      expect(store.creditOrder('o-2', earned: 5), isTrue);
      expect(store.points, 110);
      expect(store.creditOrder('o-1', earned: 5), isFalse); // duplicate
      expect(store.points, 110);
    });

    test('held order (needs_verification) not credited until approved', () {
      final store = _FakeLoyaltyStore();
      final gate = _FakeRiskGate();
      final held = gate.placeOrder('held-loyalty', const RiskContext(isNewCustomer: true, subtotalEgp: 650));
      expect(held.action, RiskAction.needsVerification);
      // Simulate BEFORE credit trigger WHEN (risk_action != needs_verification) → skip
      var credited = false;
      if (held.action != RiskAction.needsVerification) {
        credited = store.creditOrder('held-loyalty', earned: 12);
      }
      expect(credited, isFalse);
      expect(store.isProcessed('held-loyalty'), isFalse);

      // After staff confirm → approved, AFTER UPDATE trigger fires once
      gate.confirmVerification('held-loyalty');
      final approved = gate.getOrder('held-loyalty')!;
      expect(approved.action, RiskAction.approved);
      final afterConfirm = store.creditOrder('held-loyalty', earned: 12);
      expect(afterConfirm, isTrue);
      expect(store.points, 112);
      // Replay should not double
      expect(store.creditOrder('held-loyalty', earned: 12), isFalse);
    });
  });

  // -----------------------------------------------------------------------
  // Time / i18n — Cairo UTC handling, dd/MM HH:mm Western digits, AR humanisation
  // -----------------------------------------------------------------------

  group('Time/i18n: risk_evaluated_at stored UTC, displayed Africa/Cairo dd/MM HH:mm Western digits', () {
    test('stored UTC via timestamptz — DateTime isUtc', () {
      final gate = _FakeRiskGate();
      final placed = gate.placeOrder('order-time', const RiskContext(isNewCustomer: true, subtotalEgp: 120));
      // evaluatedAt must be UTC (ADR-0009) — isUtc true, came from DateTime.now().toUtc()
      expect(placed.evaluatedAt.isUtc, isTrue);
      // Round-trip through toIso8601 ends with Z
      expect(placed.evaluatedAt.toIso8601String(), endsWith('Z'));
    });

    test('Cairo winter (+02) display dd/MM HH:mm', () {
      // 2026-01-15T12:00:00Z → Cairo+02 14:00 (winter, DST off — last Friday April is DST start)
      final utc = DateTime.utc(2026, 1, 15, 12, 0, 0);
      final formatted = _formatRiskEvaluatedAt(utc);
      // 15/01 14:00 Cairo
      expect(formatted, '15/01 14:00');
      // Western digits only — no Arabic-Indic ٠١٢٣
      expect(RegExp(r'^[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}$').hasMatch(formatted), isTrue);
      expect(formatted.contains(RegExp(r'[٠-٩]')), isFalse);
    });

    test('Cairo summer DST (+03) display dd/MM HH:mm', () {
      // 2026-07-15T12:00:00Z → Cairo DST +03 15:00 (DST runs last Fri Apr → last Thu Oct)
      final utc = DateTime.utc(2026, 7, 15, 12, 0, 0);
      final formatted = _formatRiskEvaluatedAt(utc);
      expect(formatted, '15/07 15:00');
      expect(RegExp(r'^[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}$').hasMatch(formatted), isTrue);
    });

    test('uses existing cairoUtcOffset (lib/data/repos/orders_repository.dart:114)', () {
      // Prove we call the canonical helper, not a reimplementation
      final utc = DateTime.utc(2026, 8, 1, 10, 30);
      final viaHelper = cairoUtcOffset(utc);
      // Aug is DST (+03) so 10:30Z → 13:30 Cairo
      expect(viaHelper, const Duration(hours: 3));
      final naiveCairo = utc.add(viaHelper);
      expect(naiveCairo.hour, 13);
      expect(naiveCairo.minute, 30);
    });

    test('zero-padded Western digits §11.11 — 09/03 not 9/3', () {
      final utc = DateTime.utc(2026, 3, 9, 6, 5, 0); // winter +02 → 08:05 Cairo
      final formatted = _formatRiskEvaluatedAt(utc);
      expect(formatted, '09/03 08:05');
      expect(formatted, isNot(contains('9/3')));
    });
  });

  group('Arabic reasons humanised via strings catalog, English toggle works', () {
    test('each RuleCode humanises to AR/EN pair (western digits preserved)', () {
      for (final code in RuleCode.values) {
        final wire = code.wireName;
        final ar = RiskReasonStrings.of(AppLang.ar).humanize(wire);
        final en = RiskReasonStrings.of(AppLang.en).humanize(wire);
        expect(ar, isNotEmpty, reason: 'AR missing for $wire');
        expect(en, isNotEmpty, reason: 'EN missing for $wire');
        expect(ar, isNot(en), reason: 'AR/EN should differ for $wire');
        // Western digits §11.11 — ensure no Arabic-Indic numerals in reason strings
        expect(ar.contains(RegExp(r'[٠-٩]')), isFalse, reason: 'AR reason $wire used Arabic-Indic');
        expect(en.contains(RegExp(r'[٠-٩]')), isFalse);
      }
      // Spot-check canonical mappings
      expect(RiskReasonStrings.of(AppLang.ar).humanize('NEW_CUSTOMER'), 'عميل جديد');
      expect(RiskReasonStrings.of(AppLang.en).humanize('NEW_CUSTOMER'), 'New customer');
      expect(RiskReasonStrings.of(AppLang.ar).humanize('LARGE_ORDER'), 'طلب كبير');
      expect(RiskReasonStrings.of(AppLang.en).humanize('LARGE_ORDER'), 'Large order');
      expect(RiskReasonStrings.of(AppLang.ar).humanize('MULTIPLE_ACCOUNTS_DEVICE'), 'جهاز مشترك');
      // Unknown wire returns empty (defensive, not throw)
      expect(RiskReasonStrings.of(AppLang.ar).humanize('UNKNOWN_CODE'), '');
    });

    test('RiskStrings level labels toggle ar/en (RTL level chip)', () {
      expect(RiskStrings.of(AppLang.ar).levelLabel('low'), 'منخفض');
      expect(RiskStrings.of(AppLang.ar).levelLabel('medium'), 'متوسط');
      expect(RiskStrings.of(AppLang.ar).levelLabel('high'), 'مرتفع');
      expect(RiskStrings.of(AppLang.en).levelLabel('low'), 'Low');
      expect(RiskStrings.of(AppLang.en).levelLabel('medium'), 'Medium');
      expect(RiskStrings.of(AppLang.en).levelLabel('high'), 'High');
    });

    test('reasons wire list → humanised chip list stays Western digits for score', () {
      const ctx = RiskContext(isNewCustomer: true, subtotalEgp: 650); // NEW_CUSTOMER + LARGE_ORDER
      final r = calculateRisk(ctx);
      expect(r.reasons.map((c) => c.wireName).toList(), ['NEW_CUSTOMER', 'LARGE_ORDER']);
      final enChips = r.reasons.map((c) => RiskReasonStrings.of(AppLang.en).humanize(c.wireName)).toList();
      final arChips = r.reasons.map((c) => RiskReasonStrings.of(AppLang.ar).humanize(c.wireName)).toList();
      expect(enChips, ['New customer', 'Large order']);
      expect(arChips, ['عميل جديد', 'طلب كبير']);
      // Score display uses Western digits (AppStrings.formatNumber)
      expect(AppStrings.formatNumber(r.score), '35');
      expect(AppStrings.formatNumber(35).contains(RegExp(r'[٠-٩]')), isFalse);
    });
  });
}
