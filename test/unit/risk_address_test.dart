// Pure risk address tests — RISK-03 address enrichment
// Shared address increments history, same address reuse counted, never high alone.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/risk_engine.dart';
import 'package:kady_app/domain/risk_profile.dart';

void main() {
  group('RISK-03 address enrichment — history + reuse', () {
    test('shared address increments history via addressCustomerCount (when enabled)', () {
      // Default catalog has these address signals disabled (DB seed false) — server
      // ignores until geo checks land. Direct scoring requires enabled custom rules.
      final disabled = calculateRisk(const RiskContext(addressCustomerCount: 2));
      expect(disabled.score, 0);
      expect(disabled.reasons, isNot(contains(RuleCode.multipleAccountsAddress)));

      const enabledRules = [
        RiskRule(code: RuleCode.multipleAccountsAddress, score: 10, enabled: true),
      ];
      final first = calculateRisk(const RiskContext(addressCustomerCount: 1), rules: enabledRules);
      expect(first.score, 0);
      // second distinct phone using same address → MULTIPLE_ACCOUNTS_ADDRESS
      final second = calculateRisk(const RiskContext(addressCustomerCount: 2), rules: enabledRules);
      expect(second.score, 10);
      expect(second.reasons, contains(RuleCode.multipleAccountsAddress));
    });

    test('same address reuse counted — ordersAtAddress enrichment', () {
      // Simulate RISK-04 derive: SELECT count(*) FROM orders WHERE address_id = NEW.address_id
      // orders_at_address is passed as addressOrdersCount (not directly scored, but
      // available for future area checks). We verify the field is threaded through
      // RiskContext and reachable via riskContextFromProfile.
      const profile = RiskProfile(phone: '+201000000002');
      final ctx = riskContextFromProfile(
        profile,
        addressOrdersCount: 3,
        addressCustomerCount: 2,
      );
      expect(ctx.addressOrdersCount, 3);
      expect(ctx.addressCustomerCount, 2);
      // Default disabled → no reason; enabled → contains
      final disabled = calculateRisk(ctx);
      expect(disabled.reasons, isNot(contains(RuleCode.multipleAccountsAddress)));
      const enabledRules = [
        RiskRule(code: RuleCode.multipleAccountsAddress, score: 10, enabled: true),
      ];
      final enabled = calculateRisk(ctx, rules: enabledRules);
      expect(enabled.reasons, contains(RuleCode.multipleAccountsAddress));
    });

    test('addressFailedCount >=3 triggers ADDRESS_HIGH_FAILURE (when enabled)', () {
      const enabledRules = [
        RiskRule(code: RuleCode.addressHighFailure, score: 15, enabled: true),
      ];
      final low = calculateRisk(const RiskContext(addressFailedCount: 2), rules: enabledRules);
      expect(low.score, 0);
      final high = calculateRisk(const RiskContext(addressFailedCount: 3), rules: enabledRules);
      expect(high.score, 15);
      expect(high.reasons, contains(RuleCode.addressHighFailure));
      // Default disabled → 0
      final disabled = calculateRisk(const RiskContext(addressFailedCount: 3));
      expect(disabled.score, 0);
    });

    test('address reuse + failure both contribute but still capped when extrinsic-only', () {
      final r = calculateRisk(
        const RiskContext(addressCustomerCount: 2, addressFailedCount: 5),
        rules: const [
          RiskRule(code: RuleCode.multipleAccountsAddress, score: 30),
          RiskRule(code: RuleCode.addressHighFailure, score: 40),
        ],
      );
      // 70 extrinsic-only → capped to 59
      expect(r.score, lessThanOrEqualTo(59));
      expect(r.level, isNot(RiskLevel.high));
    });

    test('sharedAddressCount legacy remains unscored (RISK-01 compat)', () {
      final r = calculateRisk(const RiskContext(sharedAddressCount: 2));
      expect(r.score, 0);
      expect(r.reasons, isNot(contains(RuleCode.multipleAccountsAddress)));
      const enabledRules = [
        RiskRule(code: RuleCode.multipleAccountsAddress, score: 10, enabled: true),
      ];
      final scored = calculateRisk(const RiskContext(addressCustomerCount: 2), rules: enabledRules);
      expect(scored.reasons, contains(RuleCode.multipleAccountsAddress));
    });

    test('disabled address rules ignored', () {
      final r = calculateRisk(
        const RiskContext(addressCustomerCount: 5, addressFailedCount: 10),
        rules: const [
          RiskRule(code: RuleCode.multipleAccountsAddress, score: 10, enabled: false),
          RiskRule(code: RuleCode.addressHighFailure, score: 15, enabled: false),
        ],
      );
      expect(r.score, 0);
      expect(r.reasons, isEmpty);
    });

    test('address sharing alone never pushes to HIGH (signal not proof)', () {
      final r = calculateRisk(
        const RiskContext(addressCustomerCount: 10, addressFailedCount: 10),
        rules: const [
          RiskRule(code: RuleCode.multipleAccountsAddress, score: 35),
          RiskRule(code: RuleCode.addressHighFailure, score: 35),
        ],
      );
      expect(r.score, lessThanOrEqualTo(59));
      expect(r.level, isNot(RiskLevel.high));
      expect(r.action, isNot(RiskAction.rejected));
    });

    test('address sharing + intrinsic can reach HIGH (when address signals enabled)', () {
      // Default disabled → 20+30=50 medium; with enabled address signals 20+30+10+15=75 high
      final disabled = calculateRisk(
        const RiskContext(
          isNewCustomer: true, //20
          previousRejectedOrders: 1, //30
          addressCustomerCount: 3, //10 disabled
          addressFailedCount: 3, //15 disabled
        ),
      );
      expect(disabled.score, 50);
      expect(disabled.level, RiskLevel.medium);

      const enabledRules = [
        RiskRule(code: RuleCode.newCustomer, score: 20),
        RiskRule(code: RuleCode.previousRejectedOrder, score: 30),
        RiskRule(code: RuleCode.multipleAccountsAddress, score: 10, enabled: true),
        RiskRule(code: RuleCode.addressHighFailure, score: 15, enabled: true),
      ];
      final withNew = calculateRisk(
        const RiskContext(
          isNewCustomer: true, //20
          previousRejectedOrders: 1, //30
          addressCustomerCount: 3, //10
          addressFailedCount: 3, //15
        ),
        rules: enabledRules,
      );
      expect(withNew.score, 75);
      expect(withNew.level, RiskLevel.high);
    });

    test('riskContextFromProfile threads addressOrdersCount correctly', () {
      const profile = RiskProfile(phone: '+201000000003', totalOrders: 1);
      final ctx = riskContextFromProfile(profile, addressOrdersCount: 5);
      expect(ctx.addressOrdersCount, 5);
      // Enrichment count is stored but not directly scored — verify no crash
      final r = calculateRisk(ctx);
      // No extrinsic address rule triggered, score 0 (returning customer, no failed)
      expect(r.score, 0);
    });
  });
}
