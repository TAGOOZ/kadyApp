// Pure risk device tests — RISK-03 (signal, not proof)
// Device X → Customers A,B,C scenario, never auto-reject on device alone.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/risk_engine.dart';
import 'package:kady_app/domain/risk_profile.dart';

void main() {
  group('RISK-03 device tracking — signal not proof', () {
    test('NEW_DEVICE +10 on firstSeen for this phone+device', () {
      final r = calculateRisk(const RiskContext(isNewDevice: true));
      expect(r.score, 10);
      expect(r.reasons, contains(RuleCode.newDevice));
      expect(r.level, RiskLevel.low);
    });

    test('MULTIPLE_ACCOUNTS_DEVICE +10 when deviceCustomerCount >=2', () {
      final r = calculateRisk(const RiskContext(deviceCustomerCount: 2));
      expect(r.score, 10);
      expect(r.reasons, contains(RuleCode.multipleAccountsDevice));
    });

    test('deviceCustomerCount=1 does not trigger MULTIPLE', () {
      final r = calculateRisk(const RiskContext(deviceCustomerCount: 1));
      expect(r.score, 0);
      expect(r.reasons, isNot(contains(RuleCode.multipleAccountsDevice)));
    });

    test('sharedDeviceCount legacy remains unscored (RISK-01 compat)', () {
      final r = calculateRisk(const RiskContext(sharedDeviceCount: 2));
      expect(r.score, 0);
      expect(r.reasons, isNot(contains(RuleCode.multipleAccountsDevice)));
      // New field deviceCustomerCount is the scored path
      final scored = calculateRisk(const RiskContext(deviceCustomerCount: 2));
      expect(scored.reasons, contains(RuleCode.multipleAccountsDevice));
    });

    test('Device X → Customers A,B,C: each gets +10, 3rd still medium not high', () {
      // Customer A: first time on Device X — NEW_DEVICE
      final a = calculateRisk(const RiskContext(isNewDevice: true));
      expect(a.score, 10);
      expect(a.level, RiskLevel.low);

      // Customer B: same Device X second phone — NEW_DEVICE (first for B) + MULTIPLE
      final b = calculateRisk(
        const RiskContext(isNewDevice: true, deviceCustomerCount: 2),
      );
      expect(b.score, 20); // 10 NEW_DEVICE +10 MULTIPLE
      expect(b.reasons, containsAll([RuleCode.newDevice, RuleCode.multipleAccountsDevice]));
      expect(b.level, isNot(RiskLevel.high));
      expect(b.level, RiskLevel.low);

      // Customer C: third phone on same Device X — still only +10 MULTIPLE (plus NEW_DEVICE)
      // Even with NEW_CUSTOMER (+20) added, stays medium not high.
      final c = calculateRisk(
        const RiskContext(
          isNewCustomer: true, // +20
          isNewDevice: true, // +10
          deviceCustomerCount: 3, // +10 MULTIPLE (not +20 for 3rd)
        ),
      );
      expect(c.score, 40); // 20+10+10
      expect(c.level, RiskLevel.medium);
      expect(c.action, RiskAction.needsVerification);
      expect(c.level, isNot(RiskLevel.high));

      // Even with two extrinsics alone, never high
      final extrinsicOnlyHighAttempt = calculateRisk(
        const RiskContext(isNewDevice: true, deviceCustomerCount: 5),
        rules: const [
          RiskRule(code: RuleCode.newDevice, score: 35),
          RiskRule(code: RuleCode.multipleAccountsDevice, score: 35),
        ],
      );
      // 70 would be high, but extrinsic-only cap forces medium
      expect(extrinsicOnlyHighAttempt.score, 59);
      expect(extrinsicOnlyHighAttempt.level, RiskLevel.medium);
    });

    test('3rd customer still medium not high — pure extrinsic never high', () {
      // Simulate admin tuning where extrinsic scores are high but should cap
      const highExtrinsicRules = [
        RiskRule(code: RuleCode.newDevice, score: 40),
        RiskRule(code: RuleCode.multipleAccountsDevice, score: 40),
      ];
      final r = calculateRisk(
        const RiskContext(isNewDevice: true, deviceCustomerCount: 3),
        rules: highExtrinsicRules,
      );
      expect(r.score, lessThanOrEqualTo(59));
      expect(r.level, isNot(RiskLevel.high));
    });

    test('disabled MULTIPLE rule ignored (tunable via risk_rules)', () {
      final r = calculateRisk(
        const RiskContext(deviceCustomerCount: 2),
        rules: const [
          RiskRule(code: RuleCode.multipleAccountsDevice, score: 10, enabled: false),
        ],
      );
      expect(r.score, 0);
      expect(r.reasons, isEmpty);
    });

    test('device + intrinsic can still reach high (not capped when mixed)', () {
      final r = calculateRisk(
        const RiskContext(
          isNewCustomer: true, // 20
          previousRejectedOrders: 1, // 30
          deviceCustomerCount: 2, // 10 extrinsic
        ),
      );
      // 20+30+10 =60 → high allowed because not extrinsic-only
      expect(r.score, 60);
      expect(r.level, RiskLevel.high);
      expect(r.action, RiskAction.rejected);
    });

    test('device events are deterministic (same input → same output)', () {
      const ctx = RiskContext(isNewDevice: true, deviceCustomerCount: 2);
      final a = calculateRisk(ctx);
      final b = calculateRisk(ctx);
      expect(a.score, b.score);
      expect(a.level, b.level);
      expect(a.reasons, b.reasons);
    });

    test('RiskContext extended fields exist and riskContextFromProfile bridges them', () {
      const profile = RiskProfile(phone: '+201000000001', totalOrders: 1, successfulOrders: 1);
      final ctx = riskContextFromProfile(
        profile,
        isNewDevice: true,
        deviceCustomerCount: 2,
        addressCustomerCount: 2,
        addressFailedCount: 3,
      );
      expect(ctx.isNewDevice, isTrue);
      expect(ctx.deviceCustomerCount, 2);
      expect(ctx.addressCustomerCount, 2);
      expect(ctx.addressFailedCount, 3);
      final r = calculateRisk(ctx);
      expect(r.reasons, contains(RuleCode.newDevice));
      expect(r.reasons, contains(RuleCode.multipleAccountsDevice));
    });

    test('RuleCode wireNames for new codes round-trip', () {
      expect(RuleCode.multipleAccountsDevice.wireName, 'MULTIPLE_ACCOUNTS_DEVICE');
      expect(RuleCode.multipleAccountsAddress.wireName, 'MULTIPLE_ACCOUNTS_ADDRESS');
      expect(RuleCode.addressHighFailure.wireName, 'ADDRESS_HIGH_FAILURE');
      expect(RuleCodeX.fromWire('MULTIPLE_ACCOUNTS_DEVICE'), RuleCode.multipleAccountsDevice);
    });
  });
}
