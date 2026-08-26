// Pure risk profile helpers — RISK-02 (CONTEXT.md: phone = business key).
// No Riverpod, no Supabase — deterministic and fully unit-testable.
// Mirrors the DB table `customer_risk_profiles` (migration 0018). Keep Dart and
// SQL in sync when changing counters or thresholds (see classifyRiskEventType
// RegExps must match sync_risk_profile() in 0018).

import 'risk_engine.dart';

/// Aggregated risk identity per Customer (phone = PK FK customers.phone).
/// Server-authoritative counters mutated only via trigger sync_risk_profile().
class RiskProfile {
  const RiskProfile({
    required this.phone,
    this.totalOrders = 0,
    this.successfulOrders = 0,
    this.cancelledOrders = 0,
    this.failedDeliveries = 0,
    this.rejectedOrders = 0,
    this.totalSpent = 0,
    this.lastOrderAt,
    this.phoneVerified = false,
    this.riskScore = 0,
    this.riskLevel,
    this.createdAt,
    this.updatedAt,
  });

  final String phone;
  final int totalOrders;
  final int successfulOrders;
  final int cancelledOrders;
  final int failedDeliveries;
  final int rejectedOrders;
  final int totalSpent;
  final DateTime? lastOrderAt;
  final bool phoneVerified;
  final int riskScore;
  final RiskLevel? riskLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Parse a row from `customer_risk_profiles` (Supabase `select()` map).
  /// Tolerates snake_case keys and nullable strings/ints; missing numerics
  /// fall back to 0, bools to false — offline-safe. Keeps UTC (ADR-0009).
  factory RiskProfile.fromRow(Map<String, dynamic> row) {
    DateTime? parseTs(Object? v) {
      if (v is DateTime) return v.toUtc();
      if (v is String) return DateTime.tryParse(v)?.toUtc();
      return null;
    }

    int intFor(String key, {int fallback = 0}) {
      final v = row[key];
      if (v is int) return v;
      if (v is double) return v.round();
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) return parsed;
        final asDouble = double.tryParse(v);
        if (asDouble != null) return asDouble.round();
        return fallback;
      }
      return fallback;
    }

    bool boolFor(String key) {
      final v = row[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v.toLowerCase() == 'true' || v == '1';
      return false;
    }

    String phone = (row['phone'] as String?)?.trim() ?? '';
    if (phone.isEmpty && row['phone_number'] is String) {
      phone = (row['phone_number'] as String).trim();
    }
    if (phone.isEmpty) {
      throw ArgumentError.value(row, 'row', 'RiskProfile.fromRow: missing phone');
    }

    return RiskProfile(
      phone: phone,
      totalOrders: intFor('total_orders'),
      successfulOrders: intFor('successful_orders'),
      cancelledOrders: intFor('cancelled_orders'),
      failedDeliveries: intFor('failed_deliveries'),
      rejectedOrders: intFor('rejected_orders'),
      totalSpent: intFor('total_spent'),
      lastOrderAt: parseTs(row['last_order_at']),
      phoneVerified: boolFor('phone_verified'),
      riskScore: intFor('risk_score'),
      riskLevel: RiskLevelX.tryFromWire(row['risk_level'] as String?),
      createdAt: parseTs(row['created_at']),
      updatedAt: parseTs(row['updated_at']),
    );
  }

  Map<String, dynamic> toRow() => {
        'phone': phone,
        'total_orders': totalOrders,
        'successful_orders': successfulOrders,
        'cancelled_orders': cancelledOrders,
        'failed_deliveries': failedDeliveries,
        'rejected_orders': rejectedOrders,
        'total_spent': totalSpent,
        if (lastOrderAt != null) 'last_order_at': lastOrderAt!.toUtc().toIso8601String(),
        'phone_verified': phoneVerified,
        'risk_score': riskScore,
        if (riskLevel != null) 'risk_level': riskLevel!.wireName,
        if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  // Sentinel for copyWith to allow explicit null for nullable DateTime fields.
  static const Object _sentinel = Object();

  RiskProfile copyWith({
    String? phone,
    int? totalOrders,
    int? successfulOrders,
    int? cancelledOrders,
    int? failedDeliveries,
    int? rejectedOrders,
    int? totalSpent,
    Object? lastOrderAt = _sentinel,
    bool? phoneVerified,
    int? riskScore,
    Object? riskLevel = _sentinel,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
  }) =>
      RiskProfile(
        phone: phone ?? this.phone,
        totalOrders: totalOrders ?? this.totalOrders,
        successfulOrders: successfulOrders ?? this.successfulOrders,
        cancelledOrders: cancelledOrders ?? this.cancelledOrders,
        failedDeliveries: failedDeliveries ?? this.failedDeliveries,
        rejectedOrders: rejectedOrders ?? this.rejectedOrders,
        totalSpent: totalSpent ?? this.totalSpent,
        lastOrderAt:
            lastOrderAt == _sentinel ? this.lastOrderAt : lastOrderAt as DateTime?,
        phoneVerified: phoneVerified ?? this.phoneVerified,
        riskScore: riskScore ?? this.riskScore,
        riskLevel: riskLevel == _sentinel ? this.riskLevel : riskLevel as RiskLevel?,
        createdAt: createdAt == _sentinel ? this.createdAt : createdAt as DateTime?,
        updatedAt: updatedAt == _sentinel ? this.updatedAt : updatedAt as DateTime?,
      );

  @override
  bool operator ==(Object other) =>
      other is RiskProfile &&
      other.phone == phone &&
      other.totalOrders == totalOrders &&
      other.successfulOrders == successfulOrders &&
      other.cancelledOrders == cancelledOrders &&
      other.failedDeliveries == failedDeliveries &&
      other.rejectedOrders == rejectedOrders &&
      other.totalSpent == totalSpent &&
      other.lastOrderAt == lastOrderAt &&
      other.phoneVerified == phoneVerified &&
      other.riskScore == riskScore &&
      other.riskLevel == riskLevel &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        phone,
        totalOrders,
        successfulOrders,
        cancelledOrders,
        failedDeliveries,
        rejectedOrders,
        totalSpent,
        lastOrderAt,
        phoneVerified,
        riskScore,
        riskLevel,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'RiskProfile(phone:$phone total:$totalOrders success:$successfulOrders cancel:$cancelledOrders failed:$failedDeliveries rejected:$rejectedOrders spent:$totalSpent verified:$phoneVerified score:$riskScore level:${riskLevel?.wireName})';
}

// ---------------------------------------------------------------------------
// Pure predicate helpers — used by the risk engine and by UI gates.
// Keep names stable; tests import these directly (issue #47 acceptance).
// ---------------------------------------------------------------------------

/// New customer when no terminal order has been counted yet.
bool isNewCustomer(RiskProfile p) => p.totalOrders == 0;

/// Returning when at least one terminal order exists.
bool isReturningCustomer(RiskProfile p) => p.totalOrders > 0;

bool hasThreePlusCancellations(RiskProfile p) => p.cancelledOrders >= 3;

bool hasPreviousFailedDelivery(RiskProfile p) => p.failedDeliveries > 0;

bool hasFailedDeliveries(RiskProfile p) => hasPreviousFailedDelivery(p);

bool hasPreviousRejectedOrder(RiskProfile p) => p.rejectedOrders > 0;

bool hasRejectedOrders(RiskProfile p) => hasPreviousRejectedOrder(p);

bool hasThreePlusSuccessful(RiskProfile p) => p.successfulOrders >= 3;

bool hasFivePlusSuccessful(RiskProfile p) => p.successfulOrders >= 5;

bool isVerifiedPhone(RiskProfile p) => p.phoneVerified;

bool hasVerifiedPhone(RiskProfile p) => p.phoneVerified;

// ---------------------------------------------------------------------------
// Engine bridge — build a RiskContext from a profile + call-site flags.
// Pure; no I/O. Lets callers keep a single source of truth for mapping.
// ---------------------------------------------------------------------------

/// Convenience: derive a [RiskContext] from a persisted [RiskProfile] plus
/// transient signals (large/rapid/device) supplied by the caller.
RiskContext riskContextFromProfile(
  RiskProfile profile, {
  int subtotalEgp = 0,
  bool isNewDevice = false,
  bool isLargeOrder = false,
  bool isRapidOrders = false,
  int sharedDeviceCount = 0,
  int sharedAddressCount = 0,
}) =>
    RiskContext(
      subtotalEgp: subtotalEgp,
      isNewCustomer: isNewCustomer(profile),
      isNewDevice: isNewDevice,
      previousFailedDeliveries: profile.failedDeliveries,
      previousRejectedOrders: profile.rejectedOrders,
      cancellationsCount: profile.cancelledOrders,
      successfulOrders: profile.successfulOrders,
      isVerifiedPhone: profile.phoneVerified,
      isLargeOrder: isLargeOrder,
      isRapidOrders: isRapidOrders,
      sharedDeviceCount: sharedDeviceCount,
      sharedAddressCount: sharedAddressCount,
    );

/// Append-only ledger event — mirrors `risk_events` row.
class RiskEvent {
  const RiskEvent({
    required this.id,
    this.phone,
    this.orderId,
    this.deviceId,
    required this.eventType,
    this.metadata = const {},
    this.createdAt,
  });

  final int id;
  final String? phone;
  final String? orderId;
  final String? deviceId;
  final String eventType;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  factory RiskEvent.fromRow(Map<String, dynamic> row) {
    DateTime? parseTs(Object? v) {
      if (v is DateTime) return v.toUtc();
      if (v is String) return DateTime.tryParse(v)?.toUtc();
      return null;
    }

    int parseId(Object? v) {
      if (v is int) {
        if (v <= 0) throw ArgumentError.value(v, 'id', 'risk_events id must be >0');
        return v;
      }
      if (v is num) {
        final i = v.toInt();
        if (i <= 0) throw ArgumentError.value(v, 'id', 'risk_events id must be >0');
        return i;
      }
      if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed > 0) return parsed;
        throw ArgumentError.value(v, 'id', 'risk_events id must be >0');
      }
      throw ArgumentError.value(v, 'id', 'risk_events id must be >0');
    }

    Map<String, dynamic> parseMeta(Object? v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return const {};
    }

    return RiskEvent(
      id: parseId(row['id']),
      phone: row['phone'] as String?,
      orderId: row['order_id'] as String? ?? row['orderId'] as String?,
      deviceId: row['device_id'] as String? ?? row['deviceId'] as String?,
      eventType: (row['event_type'] as String?) ?? (row['eventType'] as String?) ?? '',
      metadata: parseMeta(row['metadata']),
      createdAt: parseTs(row['created_at'] ?? row['createdAt']),
    );
  }
}

// ---------------------------------------------------------------------------
// Post-order outcome classification — mirrors SQL sync_risk_profile().
// Pure, tested in risk_events_test.dart; keep Dart and SQL identical.
// ---------------------------------------------------------------------------

/// Canonical event codes emitted by sync_risk_profile() (constrained subset
/// of the unconstrained risk_events.event_type column).
class RiskEventType {
  static const successfulOrder = 'SUCCESSFUL_ORDER';
  static const cancelledOrder = 'CANCELLED_ORDER';
  static const rejectedOrder = 'REJECTED_ORDER';
  static const failedDelivery = 'FAILED_DELIVERY';
}

// Keep RegExps static to avoid per-call allocation; patterns must match
// SQL ~* 'refused|rejected' and ~* 'failed.*delivery|delivery.*failed|failed_delivery'.
// Note: `failed.*delivery` already matches `failed_delivery` (dot matches `_`),
// third alternative kept for explicit parity with SQL comment in 0018.
final RegExp _rejectedRe = RegExp(r'refused|rejected', caseSensitive: false);
final RegExp _failedDeliveryRe =
    RegExp(r'failed.*delivery|delivery.*failed|failed_delivery', caseSensitive: false);
final RegExp _cancelRe = RegExp(r'cancel', caseSensitive: false);

/// Mirrors the SQL branching in sync_risk_profile():
/// - done          → SUCCESSFUL_ORDER
/// - cancelled + reject_reason ~* 'refused|rejected' → REJECTED_ORDER
/// - cancelled + reject_reason ~* 'failed.*delivery|delivery.*failed|failed_delivery' → FAILED_DELIVERY
/// - cancelled + ilike '%cancel%' → CANCELLED_ORDER
/// - cancelled (else) → CANCELLED_ORDER
/// - other statuses → null (no event)
/// Returns null when no ledger event should be emitted.
String? classifyRiskEventType({
  required String oldStatus,
  required String newStatus,
  String? rejectReason,
}) {
  if (oldStatus == newStatus) return null;
  if (newStatus == 'done') return RiskEventType.successfulOrder;
  if (newStatus == 'cancelled') {
    if (rejectReason != null) {
      // Rejected check first (same priority as SQL).
      if (_rejectedRe.hasMatch(rejectReason)) {
        return RiskEventType.rejectedOrder;
      }
      if (_failedDeliveryRe.hasMatch(rejectReason)) {
        return RiskEventType.failedDelivery;
      }
      if (_cancelRe.hasMatch(rejectReason)) return RiskEventType.cancelledOrder;
    }
    return RiskEventType.cancelledOrder;
  }
  return null;
}

/// Pure counter transition — mirrors the UPDATE ... SET in sync_risk_profile.
/// Deterministic: inject [nowUtc] for tests; defaults to `DateTime.now().toUtc()`.
/// Returns the updated profile (copyWith) or the original when no transition.
RiskProfile applyRiskEventToProfile(
  RiskProfile profile, {
  required String oldStatus,
  required String newStatus,
  String? rejectReason,
  int orderTotal = 0,
  DateTime? nowUtc,
}) {
  final event = classifyRiskEventType(
    oldStatus: oldStatus,
    newStatus: newStatus,
    rejectReason: rejectReason,
  );
  if (event == null) return profile;
  final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
  switch (event) {
    case RiskEventType.successfulOrder:
      return profile.copyWith(
        totalOrders: profile.totalOrders + 1,
        successfulOrders: profile.successfulOrders + 1,
        totalSpent: profile.totalSpent + orderTotal,
        lastOrderAt: now,
      );
    case RiskEventType.cancelledOrder:
      return profile.copyWith(
        totalOrders: profile.totalOrders + 1,
        cancelledOrders: profile.cancelledOrders + 1,
        lastOrderAt: now,
      );
    case RiskEventType.rejectedOrder:
      return profile.copyWith(
        totalOrders: profile.totalOrders + 1,
        rejectedOrders: profile.rejectedOrders + 1,
        lastOrderAt: now,
      );
    case RiskEventType.failedDelivery:
      return profile.copyWith(
        totalOrders: profile.totalOrders + 1,
        failedDeliveries: profile.failedDeliveries + 1,
        lastOrderAt: now,
      );
    default:
      return profile;
  }
}
