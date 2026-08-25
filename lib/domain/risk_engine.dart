// Pure risk engine — RISK-01 foundation (FEATURES §11 + plan §7).
// No Riverpod, no Supabase, no clocks — deterministic and fully
// unit-testable. Mirrors the SQL logic that will be wired in RISK-04
// (BEFORE INSERT trigger / evaluate_order_risk RPC). Keep Dart and SQL
// identical when changing either.
//
// Thresholds are injectable via RiskConfig (offline fallbacks match
// app_config seeds in 0017_risk_foundation.sql). Rule scores and
// enabled-flags are injectable via List<RiskRule> (fallback defaults
// match risk_rules seeds §7); disabled rules are ignored.

/// Risk level wire vocabulary — stored in orders.risk_level.
enum RiskLevel { low, medium, high }

extension RiskLevelX on RiskLevel {
  String get wireName => switch (this) {
        RiskLevel.low => 'low',
        RiskLevel.medium => 'medium',
        RiskLevel.high => 'high',
      };

  static RiskLevel fromWire(String wire) => switch (wire) {
        'low' => RiskLevel.low,
        'medium' => RiskLevel.medium,
        'high' => RiskLevel.high,
        _ => throw ArgumentError.value(wire, 'wire', 'unknown RiskLevel'),
      };
}

/// Risk action wire vocabulary — stored in orders.risk_action.
enum RiskAction { approved, needsVerification, rejected }

extension RiskActionX on RiskAction {
  String get wireName => switch (this) {
        RiskAction.approved => 'approved',
        RiskAction.needsVerification => 'needs_verification',
        RiskAction.rejected => 'rejected',
      };

  static RiskAction fromWire(String wire) => switch (wire) {
        'approved' => RiskAction.approved,
        'needs_verification' => RiskAction.needsVerification,
        'rejected' => RiskAction.rejected,
        _ => throw ArgumentError.value(wire, 'wire', 'unknown RiskAction'),
      };
}

/// Canonical rule codes — match risk_rules.rule_code seeds (plan §7).
enum RuleCode {
  newCustomer,
  newDevice,
  previousFailedDelivery,
  previousRejectedOrder,
  threePlusCancellations,
  largeOrder,
  rapidOrders,
  threePlusSuccessful,
  fivePlusSuccessful,
  verifiedPhone,
}

extension RuleCodeX on RuleCode {
  String get wireName => switch (this) {
        RuleCode.newCustomer => 'NEW_CUSTOMER',
        RuleCode.newDevice => 'NEW_DEVICE',
        RuleCode.previousFailedDelivery => 'PREVIOUS_FAILED_DELIVERY',
        RuleCode.previousRejectedOrder => 'PREVIOUS_REJECTED_ORDER',
        RuleCode.threePlusCancellations => 'THREE_PLUS_CANCELLATIONS',
        RuleCode.largeOrder => 'LARGE_ORDER',
        RuleCode.rapidOrders => 'RAPID_ORDERS',
        RuleCode.threePlusSuccessful => 'THREE_PLUS_SUCCESSFUL',
        RuleCode.fivePlusSuccessful => 'FIVE_PLUS_SUCCESSFUL',
        RuleCode.verifiedPhone => 'VERIFIED_PHONE',
      };

  static RuleCode fromWire(String wire) => switch (wire) {
        'NEW_CUSTOMER' => RuleCode.newCustomer,
        'NEW_DEVICE' => RuleCode.newDevice,
        'PREVIOUS_FAILED_DELIVERY' => RuleCode.previousFailedDelivery,
        'PREVIOUS_REJECTED_ORDER' => RuleCode.previousRejectedOrder,
        'THREE_PLUS_CANCELLATIONS' => RuleCode.threePlusCancellations,
        'LARGE_ORDER' => RuleCode.largeOrder,
        'RAPID_ORDERS' => RuleCode.rapidOrders,
        'THREE_PLUS_SUCCESSFUL' => RuleCode.threePlusSuccessful,
        'FIVE_PLUS_SUCCESSFUL' => RuleCode.fivePlusSuccessful,
        'VERIFIED_PHONE' => RuleCode.verifiedPhone,
        _ => throw ArgumentError.value(wire, 'wire', 'unknown RuleCode'),
      };
}

// ---------------------------------------------------------------------------
// Config — seed constants (offline fallbacks) + parse from app_config rows
// ---------------------------------------------------------------------------

const int kRiskLowMaxScore = 29;
const int kRiskMediumMaxScore = 59;
const int kRiskLargeOrderThreshold = 500;
const int kRiskRapidOrdersCount = 3;
const int kRiskRapidOrdersWindowMinutes = 30;
const int kRiskMaxVerificationAttempts = 5;
const int kRiskVerificationExpiryMinutes = 15;

/// Immutable snapshot of admin-editable risk thresholds.
class RiskConfig {
  const RiskConfig({
    this.lowMaxScore = kRiskLowMaxScore,
    this.mediumMaxScore = kRiskMediumMaxScore,
    this.largeOrderThreshold = kRiskLargeOrderThreshold,
    this.rapidOrdersCount = kRiskRapidOrdersCount,
    this.rapidOrdersWindowMinutes = kRiskRapidOrdersWindowMinutes,
    this.maxVerificationAttempts = kRiskMaxVerificationAttempts,
    this.verificationExpiryMinutes = kRiskVerificationExpiryMinutes,
  })  : assert(lowMaxScore < mediumMaxScore,
            'lowMaxScore must be < mediumMaxScore'),
        assert(lowMaxScore >= 0 && mediumMaxScore <= 100,
            'thresholds must be within 0..100');

  static const RiskConfig fallback = RiskConfig();

  final int lowMaxScore;
  final int mediumMaxScore;
  final int largeOrderThreshold;
  final int rapidOrdersCount;
  final int rapidOrdersWindowMinutes;
  final int maxVerificationAttempts;
  final int verificationExpiryMinutes;

  /// Parses flat {key: scalar} map from app_config. Keys may be dotted
  /// (risk.low_max_score) or underscored (risk_low_max_score); bare
  /// low_max_score also accepted. Unknown/missing keys keep seed defaults.
  factory RiskConfig.fromMap(Map<String, dynamic> map) {
    int intFor(List<String> candidates, int fallback) {
      for (final k in candidates) {
        final v = map[k];
        if (v is num) return v is int ? v : v.round();
        if (v is String) {
          final parsed = int.tryParse(v);
          if (parsed != null) return parsed;
          final asDouble = double.tryParse(v);
          if (asDouble != null) return asDouble.round();
        }
      }
      return fallback;
    }

    return RiskConfig(
      lowMaxScore: intFor(
        ['risk.low_max_score', 'risk_low_max_score', 'low_max_score'],
        RiskConfig.fallback.lowMaxScore,
      ),
      mediumMaxScore: intFor(
        ['risk.medium_max_score', 'risk_medium_max_score', 'medium_max_score'],
        RiskConfig.fallback.mediumMaxScore,
      ),
      largeOrderThreshold: intFor(
        [
          'risk.large_order_threshold',
          'risk_large_order_threshold',
          'large_order_threshold'
        ],
        RiskConfig.fallback.largeOrderThreshold,
      ),
      rapidOrdersCount: intFor(
        [
          'risk.rapid_orders_count',
          'risk_rapid_orders_count',
          'rapid_orders_count'
        ],
        RiskConfig.fallback.rapidOrdersCount,
      ),
      rapidOrdersWindowMinutes: intFor(
        [
          'risk.rapid_orders_window_minutes',
          'risk_rapid_orders_window_minutes',
          'rapid_orders_window_minutes'
        ],
        RiskConfig.fallback.rapidOrdersWindowMinutes,
      ),
      maxVerificationAttempts: intFor(
        [
          'risk.max_verification_attempts',
          'risk_max_verification_attempts',
          'max_verification_attempts'
        ],
        RiskConfig.fallback.maxVerificationAttempts,
      ),
      verificationExpiryMinutes: intFor(
        [
          'risk.verification_expiry_minutes',
          'risk_verification_expiry_minutes',
          'verification_expiry_minutes'
        ],
        RiskConfig.fallback.verificationExpiryMinutes,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rules — catalog with scores + enabled flag (mirrors risk_rules table)
// ---------------------------------------------------------------------------

class RiskRule {
  const RiskRule({
    required this.code,
    required this.score,
    this.enabled = true,
    this.description,
  });

  final RuleCode code;
  final int score;
  final bool enabled;
  final String? description;
}

/// Default catalog — scores match plan §7 and 0017 seeds; enabled honoured.
const List<RiskRule> kDefaultRiskRules = [
  RiskRule(code: RuleCode.newCustomer, score: 20, description: 'First order for this phone'),
  RiskRule(code: RuleCode.newDevice, score: 10, description: 'First order from this device'),
  RiskRule(code: RuleCode.previousFailedDelivery, score: 25, description: 'Prior failed delivery'),
  RiskRule(code: RuleCode.previousRejectedOrder, score: 30, description: 'Prior rejected order'),
  RiskRule(code: RuleCode.threePlusCancellations, score: 25, description: 'Three or more cancellations'),
  RiskRule(code: RuleCode.largeOrder, score: 15, description: 'Order subtotal >= large threshold'),
  RiskRule(code: RuleCode.rapidOrders, score: 20, description: 'Rapid orders within window'),
  RiskRule(code: RuleCode.threePlusSuccessful, score: -20, description: 'Three or more successful orders'),
  RiskRule(code: RuleCode.fivePlusSuccessful, score: -30, description: 'Five or more successful orders'),
  RiskRule(code: RuleCode.verifiedPhone, score: -15, description: 'Phone verified'),
];

// ---------------------------------------------------------------------------
// Context → Result
// ---------------------------------------------------------------------------

/// Inputs to the risk engine — all derived server-side before evaluation
/// (customer_risk_profiles, customer_devices, addresses, recent orders).
/// No auth, no clocks, no I/O.
class RiskContext {
  const RiskContext({
    this.subtotalEgp = 0,
    this.isNewCustomer = false,
    this.isNewDevice = false,
    this.previousFailedDeliveries = 0,
    this.previousRejectedOrders = 0,
    this.cancellationsCount = 0,
    this.successfulOrders = 0,
    this.isVerifiedPhone = false,
    this.isLargeOrder = false,
    this.isRapidOrders = false,
    this.sharedDeviceCount = 0,
    this.sharedAddressCount = 0,
  });

  final int subtotalEgp;
  final bool isNewCustomer;
  final bool isNewDevice;
  final int previousFailedDeliveries;
  final int previousRejectedOrders;
  final int cancellationsCount;
  final int successfulOrders;
  final bool isVerifiedPhone;
  final bool isLargeOrder;
  final bool isRapidOrders;

  /// Extrinsic signals (RISK-03) — stored but not scored in RISK-01.
  /// Kept for future signal-not-proof scoring; currently ignored.
  final int sharedDeviceCount;
  final int sharedAddressCount;
}

/// Engine output — persisted to orders.risk_*.
class RiskResult {
  const RiskResult({
    required this.score,
    required this.level,
    required this.reasons,
    required this.action,
  });

  final int score;
  final RiskLevel level;
  final List<RuleCode> reasons;
  final RiskAction action;
}

// ---------------------------------------------------------------------------
// Pure engine
// ---------------------------------------------------------------------------

RiskLevel _levelForScore(int score, RiskConfig config) {
  // Defensive: normalize if admin mis-edited thresholds out of order.
  final low = config.lowMaxScore < config.mediumMaxScore
      ? config.lowMaxScore
      : config.mediumMaxScore;
  final medium = config.lowMaxScore < config.mediumMaxScore
      ? config.mediumMaxScore
      : config.lowMaxScore;
  if (score <= low) return RiskLevel.low;
  if (score <= medium) return RiskLevel.medium;
  return RiskLevel.high;
}

RiskAction _actionForScore(int score, RiskConfig config) {
  // Action thresholds mirror level thresholds (configurable via same config).
  // low → approved, medium → needs_verification, high → rejected.
  final low = config.lowMaxScore < config.mediumMaxScore
      ? config.lowMaxScore
      : config.mediumMaxScore;
  final medium = config.lowMaxScore < config.mediumMaxScore
      ? config.mediumMaxScore
      : config.lowMaxScore;
  if (score <= low) return RiskAction.approved;
  if (score <= medium) return RiskAction.needsVerification;
  return RiskAction.rejected;
}

/// Deterministic risk evaluation — no DateTime.now, no I/O.
///
/// Scoring matches plan §7; disabled rules in [rules] are ignored; thresholds
/// come from [config] (fallback = risk.low/medium_max). Result score is
/// clamped 0..100; level/action derived from config (not hardcoded switch).
RiskResult calculateRisk(
  RiskContext context, {
  RiskConfig config = RiskConfig.fallback,
  List<RiskRule>? rules,
}) {
  final catalog = rules ?? kDefaultRiskRules;
  // Index by RuleCode for O(1) lookup and enabled check.
  final byCode = {for (final r in catalog) r.code: r};
  if (byCode.length != catalog.length) {
    throw ArgumentError('duplicate RuleCode in risk catalog');
  }

  int score = 0;
  final reasons = <RuleCode>[];

  void apply(RuleCode code, bool condition) {
    if (!condition) return;
    final rule = byCode[code];
    if (rule == null || !rule.enabled) return;
    score += rule.score;
    reasons.add(code);
  }

  apply(RuleCode.newCustomer, context.isNewCustomer);
  apply(RuleCode.newDevice, context.isNewDevice);
  apply(
    RuleCode.previousFailedDelivery,
    context.previousFailedDeliveries > 0,
  );
  apply(
    RuleCode.previousRejectedOrder,
    context.previousRejectedOrders > 0,
  );
  apply(
    RuleCode.threePlusCancellations,
    context.cancellationsCount >= 3,
  );

  // Large order: explicit flag OR threshold check (server recomputes from menu_items§16).
  final isLarge = context.isLargeOrder ||
      context.subtotalEgp >= config.largeOrderThreshold;
  apply(RuleCode.largeOrder, isLarge);

  apply(RuleCode.rapidOrders, context.isRapidOrders);

  // Successful-order bonuses are exclusive: 5+ supersedes 3+, but
  // fallback to 3+ when 5+ is disabled (admin tuning).
  final fiveRule = byCode[RuleCode.fivePlusSuccessful];
  final threeRule = byCode[RuleCode.threePlusSuccessful];
  final hasFive = fiveRule != null && fiveRule.enabled;
  final hasThree = threeRule != null && threeRule.enabled;
  if (context.successfulOrders >= 5 && hasFive) {
    apply(RuleCode.fivePlusSuccessful, true);
  } else if (context.successfulOrders >= 3 && hasThree) {
    apply(RuleCode.threePlusSuccessful, true);
  }

  apply(RuleCode.verifiedPhone, context.isVerifiedPhone);

  // sharedDeviceCount / sharedAddressCount intentionally not scored in RISK-01
  // (signal, not proof — RISK-03 will add MULTIPLE_ACCOUNTS_DEVICE etc.).

  // Clamp to DB check constraint 0..100; negative bonuses not below 0.
  if (score < 0) score = 0;
  if (score > 100) score = 100;

  final level = _levelForScore(score, config);
  final action = _actionForScore(score, config);

  return RiskResult(
    score: score,
    level: level,
    reasons: List.unmodifiable(reasons),
    action: action,
  );
}
