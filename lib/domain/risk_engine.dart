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

  /// Null-tolerant variant for historic nullable `orders.risk_level`.
  /// Returns null on null/unknown instead of throwing.
  static RiskLevel? tryFromWire(String? wire) {
    if (wire == null) return null;
    try {
      return fromWire(wire);
    } on ArgumentError {
      return null;
    }
  }
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

  /// Null-tolerant variant for historic nullable `orders.risk_action`.
  static RiskAction? tryFromWire(String? wire) {
    if (wire == null) return null;
    try {
      return fromWire(wire);
    } on ArgumentError {
      return null;
    }
  }
}

/// Canonical rule codes — match risk_rules.rule_code seeds (plan §7).
/// RISK-03 adds MULTIPLE_ACCOUNTS_* as extrinsic signals (signal, not proof).
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
  multipleAccountsDevice,
  multipleAccountsAddress,
  addressHighFailure,
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
        RuleCode.multipleAccountsDevice => 'MULTIPLE_ACCOUNTS_DEVICE',
        RuleCode.multipleAccountsAddress => 'MULTIPLE_ACCOUNTS_ADDRESS',
        RuleCode.addressHighFailure => 'ADDRESS_HIGH_FAILURE',
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
        'MULTIPLE_ACCOUNTS_DEVICE' => RuleCode.multipleAccountsDevice,
        'MULTIPLE_ACCOUNTS_ADDRESS' => RuleCode.multipleAccountsAddress,
        'ADDRESS_HIGH_FAILURE' => RuleCode.addressHighFailure,
        _ => throw ArgumentError.value(wire, 'wire', 'unknown RuleCode'),
      };

  /// Null-tolerant variant; returns null on null/unknown.
  static RuleCode? tryFromWire(String? wire) {
    if (wire == null) return null;
    try {
      return fromWire(wire);
    } on ArgumentError {
      return null;
    }
  }
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
  /// low_max_score also accepted. Unlike [LoyaltyRulesConfig.fromMap]
  /// (bare keys only), risk keys are namespaced so all three forms are
  /// accepted; keep strategies consistent.
  /// Unknown/missing keys keep seed defaults. Doubles/double-strings are
  /// rounded (29.9→30) not truncated. Throws [ArgumentError] if thresholds
  /// are misordered or out of 0..100 so admin mis-edits surface immediately
  /// (release-safe, not just assert).
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

    final low = intFor(
      ['risk.low_max_score', 'risk_low_max_score', 'low_max_score'],
      RiskConfig.fallback.lowMaxScore,
    );
    final medium = intFor(
      ['risk.medium_max_score', 'risk_medium_max_score', 'medium_max_score'],
      RiskConfig.fallback.mediumMaxScore,
    );
    if (low >= medium) {
      throw ArgumentError.value(
        {'low': low, 'medium': medium},
        'RiskConfig',
        'lowMaxScore must be < mediumMaxScore',
      );
    }
    if (low < 0 || medium > 100) {
      throw ArgumentError.value(
        {'low': low, 'medium': medium},
        'RiskConfig',
        'thresholds must be within 0..100',
      );
    }

    return RiskConfig(
      lowMaxScore: low,
      mediumMaxScore: medium,
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
/// `risk_rules.configuration` jsonb is reserved for per-rule tuning and
/// currently ignored by the Dart engine; keep SQL and Dart in sync (see file header).
/// RISK-03 adds MULTIPLE_ACCOUNTS_DEVICE (+10, signal not proof) — families share
/// devices/addresses, so this never auto-rejects alone (capped in calculateRisk).
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
  RiskRule(code: RuleCode.multipleAccountsDevice, score: 10, description: 'Same device used by 2+ phones (signal, not proof)'),
  RiskRule(code: RuleCode.multipleAccountsAddress, score: 10, enabled: false, description: 'Same address used by 2+ phones (signal, not proof)'),
  RiskRule(code: RuleCode.addressHighFailure, score: 15, enabled: false, description: 'Address with 3+ failed/cancelled deliveries'),
];

// ---------------------------------------------------------------------------
// Context → Result
// ---------------------------------------------------------------------------

/// Inputs to the risk engine — all derived server-side before evaluation
/// (customer_risk_profiles, customer_devices, addresses, recent orders).
/// No auth, no clocks, no I/O.
/// RISK-03: extrinsic device/address signals are signal-not-proof — shared
/// device/address raises score but never auto-rejects alone (families share).
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
    this.deviceCustomerCount = 0,
    this.addressCustomerCount = 0,
    this.addressFailedCount = 0,
    this.addressOrdersCount = 0,
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

  /// Extrinsic signals (RISK-01 legacy) — kept for backwards compat.
  /// RISK-03 prefers [deviceCustomerCount]/[addressCustomerCount].
  final int sharedDeviceCount;
  final int sharedAddressCount;

  /// RISK-03 extrinsic counts — server-derived at evaluate time:
  /// - deviceCustomerCount: distinct phones using same device_id (≥2 → MULTIPLE_ACCOUNTS_DEVICE +10)
  /// - addressCustomerCount: distinct phones using same address_id
  /// - addressFailedCount: failed/cancelled deliveries at same address
  /// - addressOrdersCount: total orders at same address (for enrichment)
  final int deviceCustomerCount;
  final int addressCustomerCount;
  final int addressFailedCount;
  final int addressOrdersCount;
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

({int low, int medium}) _normalizedThresholds(RiskConfig c) {
  // fromMap already validates low < medium; this is last-resort for
  // direct const misconstruction (assert disabled in release).
  if (c.lowMaxScore < c.mediumMaxScore) {
    return (low: c.lowMaxScore, medium: c.mediumMaxScore);
  }
  return (low: c.mediumMaxScore, medium: c.lowMaxScore);
}

RiskLevel _levelForScore(int score, RiskConfig config) {
  final t = _normalizedThresholds(config);
  if (score <= t.low) return RiskLevel.low;
  if (score <= t.medium) return RiskLevel.medium;
  return RiskLevel.high;
}

RiskAction _actionForScore(int score, RiskConfig config) {
  // Action thresholds mirror level thresholds (configurable via same config).
  // low → approved, medium → needs_verification, high → rejected.
  final t = _normalizedThresholds(config);
  if (score <= t.low) return RiskAction.approved;
  if (score <= t.medium) return RiskAction.needsVerification;
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
    final seen = <RuleCode>{};
    final dupes = <RuleCode>{};
    for (final r in catalog) {
      if (!seen.add(r.code)) dupes.add(r.code);
    }
    throw ArgumentError.value(
      catalog,
      'rules',
      'duplicate RuleCode(s): ${dupes.map((c) => c.wireName).join(', ')}',
    );
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

  // RISK-03 extrinsic signals — signal, not proof (families share devices/addresses
  // in Mahmoudia). Scores are tunable via risk_rules enabled flag.
  // Legacy sharedDeviceCount / sharedAddressCount remain unscored for RISK-01
  // backwards compat (see risk_engine_test legacy assertion); new callers should
  // use deviceCustomerCount / addressCustomerCount.
  apply(RuleCode.multipleAccountsDevice, context.deviceCustomerCount >= 2);
  apply(RuleCode.multipleAccountsAddress, context.addressCustomerCount >= 2);
  apply(RuleCode.addressHighFailure, context.addressFailedCount >= 3);

  // Also support addressOrdersCount enrichment — no direct scoring, just for future
  // area checks (counts derived via SELECT count(*) FROM orders WHERE address_id = ...).
  // Kept as field for RISK-04 evaluate-time derivation, not scored here.

  // Extrinsic-only cap: shared device/address signals alone must never push to
  // HIGH (signal not proof). If every contributing reason is extrinsic, clamp to
  // mediumMax (59) so decision stays at worst needs_verification.
  const extrinsicCodes = {
    RuleCode.newDevice,
    RuleCode.multipleAccountsDevice,
    RuleCode.multipleAccountsAddress,
    RuleCode.addressHighFailure,
  };
  final extrinsicOnly = reasons.isNotEmpty && reasons.every(extrinsicCodes.contains);
  if (extrinsicOnly && score > config.mediumMaxScore) {
    score = config.mediumMaxScore;
  }

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
