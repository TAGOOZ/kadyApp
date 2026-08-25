// Pure risk engine tests — RISK-01 (plan §7).
// No network, no Riverpod, no Supabase — deterministic only.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/risk_engine.dart';

void main() {
  // -------------------------------------------------------------------------
  // Config loader
  // -------------------------------------------------------------------------
  group('RiskConfig.fromMap — parsing + fallbacks', () {
    test('parses dotted risk.* keys (jsonb numbers and strings)', () {
      final c = RiskConfig.fromMap({
        'risk.low_max_score': 29,
        'risk.medium_max_score': '59',
        'risk.large_order_threshold': 500,
        'risk.rapid_orders_count': '3',
        'risk.rapid_orders_window_minutes': 30,
        'risk.max_verification_attempts': 5,
        'risk.verification_expiry_minutes': '15',
      });
      expect(c.lowMaxScore, 29);
      expect(c.mediumMaxScore, 59);
      expect(c.largeOrderThreshold, 500);
      expect(c.rapidOrdersCount, 3);
      expect(c.rapidOrdersWindowMinutes, 30);
      expect(c.maxVerificationAttempts, 5);
      expect(c.verificationExpiryMinutes, 15);
    });

    test('accepts underscored and bare keys', () {
      final c = RiskConfig.fromMap({
        'risk_low_max_score': 10,
        'risk_medium_max_score': 20,
        'large_order_threshold': 400,
      });
      expect(c.lowMaxScore, 10);
      expect(c.mediumMaxScore, 20);
      expect(c.largeOrderThreshold, 400);
      // unspecified keep fallback
      expect(c.rapidOrdersCount, RiskConfig.fallback.rapidOrdersCount);
    });

    test('empty/garbage map keeps every seed default', () {
      const fallback = RiskConfig.fallback;
      for (final map in [
        const <String, dynamic>{},
        {'risk.low_max_score': 'not-a-number'},
        {'risk.large_order_threshold': null},
      ]) {
        final c = RiskConfig.fromMap(map);
        expect(c.lowMaxScore, fallback.lowMaxScore);
        expect(c.mediumMaxScore, fallback.mediumMaxScore);
        expect(c.largeOrderThreshold, fallback.largeOrderThreshold);
        expect(c.rapidOrdersCount, fallback.rapidOrdersCount);
        expect(c.rapidOrdersWindowMinutes, fallback.rapidOrdersWindowMinutes);
        expect(c.maxVerificationAttempts, fallback.maxVerificationAttempts);
        expect(c.verificationExpiryMinutes, fallback.verificationExpiryMinutes);
      }
    });

    test('seed constants match migration 0017 app_config seeds', () {
      expect(kRiskLowMaxScore, 29);
      expect(kRiskMediumMaxScore, 59);
      expect(kRiskLargeOrderThreshold, 500);
      expect(kRiskRapidOrdersCount, 3);
      expect(kRiskRapidOrdersWindowMinutes, 30);
      expect(kRiskMaxVerificationAttempts, 5);
      expect(kRiskVerificationExpiryMinutes, 15);
    });

    test('fallback is usable offline', () {
      const c = RiskConfig.fallback;
      expect(c.lowMaxScore, 29);
      expect(c.mediumMaxScore, 59);
    });
  });

  // -------------------------------------------------------------------------
  // Enums wire helpers
  // -------------------------------------------------------------------------
  group('RiskLevel / RiskAction wire helpers', () {
    test('RiskLevel wireName round-trips', () {
      expect(RiskLevel.low.wireName, 'low');
      expect(RiskLevel.medium.wireName, 'medium');
      expect(RiskLevel.high.wireName, 'high');
      expect(RiskLevelX.fromWire('low'), RiskLevel.low);
      expect(RiskLevelX.fromWire('medium'), RiskLevel.medium);
      expect(RiskLevelX.fromWire('high'), RiskLevel.high);
    });

    test('RiskAction wireName round-trips', () {
      expect(RiskAction.approved.wireName, 'approved');
      expect(RiskAction.needsVerification.wireName, 'needs_verification');
      expect(RiskAction.rejected.wireName, 'rejected');
      expect(RiskActionX.fromWire('approved'), RiskAction.approved);
      expect(RiskActionX.fromWire('needs_verification'), RiskAction.needsVerification);
      expect(RiskActionX.fromWire('rejected'), RiskAction.rejected);
    });

    test('RuleCode wireName round-trips', () {
      for (final code in RuleCode.values) {
        expect(RuleCodeX.fromWire(code.wireName), code);
      }
      expect(RuleCode.newCustomer.wireName, 'NEW_CUSTOMER');
      expect(RuleCode.verifiedPhone.wireName, 'VERIFIED_PHONE');
    });
  });

  // -------------------------------------------------------------------------
  // Each rule in isolation
  // -------------------------------------------------------------------------
  group('calculateRisk — each rule in isolation (score delta)', () {
    RiskResult isolated(RiskContext ctx) => calculateRisk(ctx);

    test('NEW_CUSTOMER +20', () {
      final r = isolated(const RiskContext(isNewCustomer: true));
      expect(r.score, 20);
      expect(r.reasons, contains(RuleCode.newCustomer));
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
    });

    test('NEW_DEVICE +10', () {
      final r = isolated(const RiskContext(isNewDevice: true));
      expect(r.score, 10);
      expect(r.reasons, [RuleCode.newDevice]);
    });

    test('PREVIOUS_FAILED_DELIVERY +25', () {
      final r = isolated(const RiskContext(previousFailedDeliveries: 1));
      expect(r.score, 25);
      expect(r.reasons, [RuleCode.previousFailedDelivery]);
    });

    test('PREVIOUS_REJECTED_ORDER +30', () {
      final r = isolated(const RiskContext(previousRejectedOrders: 2));
      expect(r.score, 30);
      expect(r.reasons, [RuleCode.previousRejectedOrder]);
    });

    test('THREE_PLUS_CANCELLATIONS +25 (threshold >=3)', () {
      final r3 = isolated(const RiskContext(cancellationsCount: 3));
      expect(r3.score, 25);
      expect(r3.reasons, [RuleCode.threePlusCancellations]);
      final r2 = isolated(const RiskContext(cancellationsCount: 2));
      expect(r2.score, 0);
      expect(r2.reasons, isEmpty);
    });

    test('LARGE_ORDER +15 via isLargeOrder flag', () {
      final r = isolated(const RiskContext(isLargeOrder: true));
      expect(r.score, 15);
      expect(r.reasons, [RuleCode.largeOrder]);
    });

    test('LARGE_ORDER +15 via subtotal >= threshold (500)', () {
      final r = isolated(const RiskContext(subtotalEgp: 500));
      expect(r.score, 15);
      expect(r.reasons, [RuleCode.largeOrder]);
      final below = isolated(const RiskContext(subtotalEgp: 499));
      expect(below.score, 0);
    });

    test('RAPID_ORDERS +20', () {
      final r = isolated(const RiskContext(isRapidOrders: true));
      expect(r.score, 20);
      expect(r.reasons, [RuleCode.rapidOrders]);
    });

    test('THREE_PLUS_SUCCESSFUL -20 (3-4 orders)', () {
      final r = isolated(const RiskContext(successfulOrders: 3));
      expect(r.score, 0); // -20 clamped to 0
      expect(r.reasons, [RuleCode.threePlusSuccessful]);
      final r4 = isolated(const RiskContext(successfulOrders: 4));
      expect(r4.score, 0);
      expect(r4.reasons, [RuleCode.threePlusSuccessful]);
    });

    test('FIVE_PLUS_SUCCESSFUL -30 (5+ orders, exclusive over 3+)', () {
      final r = isolated(const RiskContext(successfulOrders: 5));
      expect(r.reasons, [RuleCode.fivePlusSuccessful]);
      expect(r.reasons, isNot(contains(RuleCode.threePlusSuccessful)));
      // -30 alone clamped to 0
      expect(r.score, 0);
      final r6 = isolated(const RiskContext(successfulOrders: 6));
      expect(r6.reasons, [RuleCode.fivePlusSuccessful]);
    });

    test('VERIFIED_PHONE -15', () {
      final r = isolated(const RiskContext(isVerifiedPhone: true));
      expect(r.score, 0); // -15 clamped
      expect(r.reasons, [RuleCode.verifiedPhone]);
    });

    test('shared counts are signals not proof — not scored in RISK-01', () {
      final r = isolated(const RiskContext(sharedDeviceCount: 5, sharedAddressCount: 10));
      expect(r.score, 0);
      expect(r.reasons, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Threshold edges 29/30/59/60
  // -------------------------------------------------------------------------
  group('calculateRisk — threshold edges 29/30/59/60', () {
    test('score 29 → low/approved, 30 → medium/needs_verification', () {
      const config = RiskConfig(lowMaxScore: 29, mediumMaxScore: 59);

      final rLowTriggered = calculateRisk(
        const RiskContext(isNewCustomer: true),
        config: config,
        rules: const [RiskRule(code: RuleCode.newCustomer, score: 29)],
      );
      expect(rLowTriggered.score, 29);
      expect(rLowTriggered.level, RiskLevel.low);
      expect(rLowTriggered.action, RiskAction.approved);

      final rMedLow = calculateRisk(
        const RiskContext(isNewCustomer: true),
        config: config,
        rules: const [RiskRule(code: RuleCode.newCustomer, score: 30)],
      );
      expect(rMedLow.score, 30);
      expect(rMedLow.level, RiskLevel.medium);
      expect(rMedLow.action, RiskAction.needsVerification);
    });

    test('59 → medium, 60 → high', () {
      const config = RiskConfig(lowMaxScore: 29, mediumMaxScore: 59);
      final r59 = calculateRisk(
        const RiskContext(isNewCustomer: true),
        config: config,
        rules: const [RiskRule(code: RuleCode.newCustomer, score: 59)],
      );
      expect(r59.level, RiskLevel.medium);
      expect(r59.action, RiskAction.needsVerification);

      final r60 = calculateRisk(
        const RiskContext(isNewCustomer: true),
        config: config,
        rules: const [RiskRule(code: RuleCode.newCustomer, score: 60)],
      );
      expect(r60.level, RiskLevel.high);
      expect(r60.action, RiskAction.rejected);
    });

    test('thresholds injectable — custom config changes level', () {
      // With low=10, medium=20, score 15 should be medium not low
      const custom = RiskConfig(lowMaxScore: 10, mediumMaxScore: 20);
      final r15 = calculateRisk(
        const RiskContext(isNewCustomer: true),
        config: custom,
        rules: const [RiskRule(code: RuleCode.newCustomer, score: 15)],
      );
      expect(r15.level, RiskLevel.medium);
      expect(r15.action, RiskAction.needsVerification);

      // Same score 15 with fallback (29/59) is low
      final rFallback = calculateRisk(
        const RiskContext(isNewCustomer: true),
        rules: const [RiskRule(code: RuleCode.newCustomer, score: 15)],
      );
      expect(rFallback.level, RiskLevel.low);
    });

    test('action configurable via same thresholds (no hardcoded switch)', () {
      const cfgA = RiskConfig(lowMaxScore: 29, mediumMaxScore: 59);
      const cfgB = RiskConfig(lowMaxScore: 5, mediumMaxScore: 10);
      // Score 7: cfgA → low/approved, cfgB → medium/needs_verification
      final a = calculateRisk(const RiskContext(isNewCustomer: true), config: cfgA, rules: const [RiskRule(code: RuleCode.newCustomer, score: 7)]);
      final b = calculateRisk(const RiskContext(isNewCustomer: true), config: cfgB, rules: const [RiskRule(code: RuleCode.newCustomer, score: 7)]);
      expect(a.action, RiskAction.approved);
      expect(b.action, RiskAction.needsVerification);
    });
  });

  // -------------------------------------------------------------------------
  // Negative modifiers clamp not below 0
  // -------------------------------------------------------------------------
  group('calculateRisk — negative modifiers clamp', () {
    test('all bonuses together clamp to 0, not negative', () {
      final r = calculateRisk(const RiskContext(
        successfulOrders: 5, // -30
        isVerifiedPhone: true, // -15
      ));
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
    });

    test('bonus with small positive still clamped correctly', () {
      // NEW_DEVICE +10, VERIFIED -15, SUCCESS 3+ -20 → 10-15-20 = -25 → 0
      final r = calculateRisk(const RiskContext(
        isNewDevice: true,
        isVerifiedPhone: true,
        successfulOrders: 3,
      ));
      expect(r.score, 0);
    });

    test('positive outweighs negative — 20+30-20=30 medium', () {
      // NEW_CUSTOMER 20 + REJECTED 30 - THREE_SUCCESS 20 = 30 → medium
      final r = calculateRisk(const RiskContext(
        isNewCustomer: true,
        previousRejectedOrders: 1,
        successfulOrders: 3,
      ));
      expect(r.score, 30);
      expect(r.level, RiskLevel.medium);
    });

    test('clamp max 100', () {
      // Sum many positives: 20+10+25+30+25+15+20 =145 → clamp 100 high
      final r = calculateRisk(const RiskContext(
        isNewCustomer: true,
        isNewDevice: true,
        previousFailedDeliveries: 1,
        previousRejectedOrders: 1,
        cancellationsCount: 3,
        isLargeOrder: true,
        isRapidOrders: true,
      ));
      expect(r.score, 100);
      expect(r.level, RiskLevel.high);
    });
  });

  // -------------------------------------------------------------------------
  // enabled=false ignored
  // -------------------------------------------------------------------------
  group('calculateRisk — disabled flags honoured', () {
    test('disabled NEW_CUSTOMER ignored', () {
      final r = calculateRisk(
        const RiskContext(isNewCustomer: true),
        rules: const [
          RiskRule(code: RuleCode.newCustomer, score: 20, enabled: false),
        ],
      );
      expect(r.score, 0);
      expect(r.reasons, isEmpty);
    });

    test('disabled LARGE_ORDER ignored even when threshold met', () {
      final r = calculateRisk(
        const RiskContext(subtotalEgp: 600),
        rules: const [
          RiskRule(code: RuleCode.largeOrder, score: 15, enabled: false),
        ],
      );
      expect(r.score, 0);
    });

    test('mix of enabled/disabled', () {
      final r = calculateRisk(
        const RiskContext(isNewCustomer: true, isNewDevice: true, isVerifiedPhone: true),
        rules: const [
          RiskRule(code: RuleCode.newCustomer, score: 20, enabled: true),
          RiskRule(code: RuleCode.newDevice, score: 10, enabled: false),
          RiskRule(code: RuleCode.verifiedPhone, score: -15, enabled: false),
        ],
      );
      expect(r.score, 20);
      expect(r.reasons, [RuleCode.newCustomer]);
      expect(r.reasons, isNot(contains(RuleCode.newDevice)));
    });

    test('all disabled → score 0', () {
      final disabledAll = kDefaultRiskRules.map((rr) => RiskRule(code: rr.code, score: rr.score, enabled: false)).toList();
      final r = calculateRisk(
        const RiskContext(
          isNewCustomer: true,
          isNewDevice: true,
          previousFailedDeliveries: 5,
          previousRejectedOrders: 5,
          cancellationsCount: 10,
          isLargeOrder: true,
          isRapidOrders: true,
          successfulOrders: 10,
          isVerifiedPhone: true,
          subtotalEgp: 1000,
        ),
        rules: disabledAll,
      );
      expect(r.score, 0);
      expect(r.reasons, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Deterministic
  // -------------------------------------------------------------------------
  group('calculateRisk — deterministic', () {
    test('same input → same output (no DateTime.now inside)', () {
      const ctx = RiskContext(
        subtotalEgp: 650,
        isNewCustomer: true,
        isNewDevice: true,
        previousFailedDeliveries: 1,
        successfulOrders: 5,
        isVerifiedPhone: true,
        isLargeOrder: true,
        isRapidOrders: true,
      );
      final a = calculateRisk(ctx);
      final b = calculateRisk(ctx);
      expect(a.score, b.score);
      expect(a.level, b.level);
      expect(a.action, b.action);
      expect(a.reasons, b.reasons);
    });

    test('repeated calls with same config produce identical results', () {
      const ctx = RiskContext(cancellationsCount: 3, successfulOrders: 4, isLargeOrder: false);
      const cfg = RiskConfig(lowMaxScore: 29, mediumMaxScore: 59);
      for (var i = 0; i < 5; i++) {
        final r = calculateRisk(ctx, config: cfg);
        expect(r.score, 5); // CANCELLATIONS 25 - THREE_SUCCESS 20 =5
        expect(r.level, RiskLevel.low);
      }
    });

    test('no wall-clock dependency — two calls separated in time equal', () async {
      const ctx = RiskContext(isNewCustomer: true);
      final r1 = calculateRisk(ctx);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final r2 = calculateRisk(ctx);
      expect(r1.score, r2.score);
      expect(r1.reasons, r2.reasons);
    });
  });

  // -------------------------------------------------------------------------
  // Integration-ish combos
  // -------------------------------------------------------------------------
  group('calculateRisk — combos & edge cases', () {
    test('new customer + large order + rapid = 20+15+20=55 medium', () {
      final r = calculateRisk(const RiskContext(
        isNewCustomer: true,
        isLargeOrder: true,
        isRapidOrders: true,
      ));
      expect(r.score, 55);
      expect(r.level, RiskLevel.medium);
      expect(r.action, RiskAction.needsVerification);
      expect(r.reasons, containsAll([RuleCode.newCustomer, RuleCode.largeOrder, RuleCode.rapidOrders]));
    });

    test('trusted returning 5+ successful + verified → bonuses outweigh', () {
      // NEW_DEVICE 10 + VERIFIED -15 + FIVE -30 = -35 → 0 low
      final r = calculateRisk(const RiskContext(
        isNewDevice: true,
        isVerifiedPhone: true,
        successfulOrders: 5,
      ));
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
    });

    test('high-risk: 3 failed + 3 cancellations + large = 25+25+15=65 high', () {
      final r = calculateRisk(const RiskContext(
        previousFailedDeliveries: 3,
        cancellationsCount: 5,
        isLargeOrder: true,
      ));
      expect(r.score, 65);
      expect(r.level, RiskLevel.high);
      expect(r.action, RiskAction.rejected);
    });

    test('empty context → 0 low approved, no reasons', () {
      final r = calculateRisk(const RiskContext());
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
      expect(r.action, RiskAction.approved);
      expect(r.reasons, isEmpty);
    });

    test('reasons list is unmodifiable', () {
      final r = calculateRisk(const RiskContext(isNewCustomer: true));
      expect(() => r.reasons.add(RuleCode.newDevice), throwsUnsupportedError);
    });

    test('large order threshold injectable via config', () {
      const lowThresh = RiskConfig(largeOrderThreshold: 100);
      const highThresh = RiskConfig(largeOrderThreshold: 1000);
      final withLow = calculateRisk(const RiskContext(subtotalEgp: 150), config: lowThresh);
      expect(withLow.reasons, contains(RuleCode.largeOrder));
      final withHigh = calculateRisk(const RiskContext(subtotalEgp: 150), config: highThresh);
      expect(withHigh.reasons, isNot(contains(RuleCode.largeOrder)));
    });
  });
}
