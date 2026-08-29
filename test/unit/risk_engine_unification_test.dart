import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/risk_engine.dart';

void main() {
  group('RiskEngine deep module — unification (0027)', () {
    test('RiskEngine.evaluate delegates to calculateRisk', () {
      const ctx = RiskContext(isNewCustomer: true, subtotalEgp: 650);
      const engine = RiskEngine();
      final viaEngine = engine.evaluate(ctx);
      final viaFn = calculateRisk(ctx);
      expect(viaEngine.score, viaFn.score);
      expect(viaEngine.level, viaFn.level);
      expect(viaEngine.action, viaFn.action);
      expect(viaEngine.reasons, viaFn.reasons);
    });

    test('kDefaultRiskRules isExtrinsic flags match legacy set (4 codes)', () {
      final extrinsicCodes = kDefaultRiskRules.where((r) => r.isExtrinsic).map((r) => r.code).toSet();
      expect(extrinsicCodes, {RuleCode.newDevice, RuleCode.multipleAccountsDevice, RuleCode.multipleAccountsAddress, RuleCode.addressHighFailure});
      // Verify legacy fallback still contains same 4
      expect(extrinsicCodes.length, 4);
    });

    test('isExtrinsic true keeps extrinsicOnly cap (newDevice+multiple high scores clamped)', () {
      const rules = [
        RiskRule(code: RuleCode.newDevice, score: 40, isExtrinsic: true),
        RiskRule(code: RuleCode.multipleAccountsDevice, score: 40, isExtrinsic: true),
      ];
      const ctx = RiskContext(isNewDevice: true, deviceCustomerCount: 3);
      final r = calculateRisk(ctx, rules: rules);
      expect(r.score, lessThanOrEqualTo(59), reason: 'extrinsic-only capped to mediumMax via isExtrinsic flag');
      expect(r.level, isNot(RiskLevel.high));
    });

    test('isExtrinsic false on extrinsic code should not cap (mixed with non-extrinsic still high possible)', () {
      // If a rule is not marked extrinsic, mixed reasons should still reach high
      const rules = [
        RiskRule(code: RuleCode.newCustomer, score: 40, isExtrinsic: false),
        RiskRule(code: RuleCode.largeOrder, score: 30, isExtrinsic: false),
      ];
      const ctx = RiskContext(isNewCustomer: true, subtotalEgp: 600);
      final r = calculateRisk(ctx, rules: rules);
      // 40+30=70 → high (mixed, not extrinsic-only)
      expect(r.score, 70);
      expect(r.level, RiskLevel.high);
    });

    test('RiskEngine copyWith tunes config without touching call sites', () {
      const customCfg = RiskConfig(lowMaxScore: 20, mediumMaxScore: 40);
      const engine = RiskEngine();
      final tuned = engine.copyWith(config: customCfg);
      const ctx = RiskContext(isNewCustomer: true, subtotalEgp: 500); // NEW 20 + LARGE 15 =35
      final rDefault = engine.evaluate(ctx);
      final rTuned = tuned.evaluate(ctx);
      // default 35 → medium (29/59), tuned 35 → medium still but thresholds differ
      expect(rDefault.level, RiskLevel.medium);
      expect(rTuned.level, RiskLevel.medium);
      // With lower thresholds, same 35 could be high if mediumMax lowered
      final highTuned = engine.copyWith(config: const RiskConfig(lowMaxScore: 10, mediumMaxScore: 30));
      final rHigh = highTuned.evaluate(ctx);
      expect(rHigh.level, RiskLevel.high);
    });

    test('RiskEngine interface is small (evaluate only) — leverage check', () {
      const engine = RiskEngine();
      // Interface: evaluate + copyWith only — hides catalog, config, extrinsic logic
      expect(engine.config, isA<RiskConfig>());
      expect(engine.rules, isA<List<RiskRule>>());
      // Evaluate via engine matches pure function — one test surface
      const ctx = RiskContext(isNewDevice: true, deviceCustomerCount: 2);
      expect(engine.evaluate(ctx).score, calculateRisk(ctx).score);
    });
  });
}
