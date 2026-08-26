// ignore_for_file: prefer_initializing_formals, curly_braces_in_flow_control_structures

// Provider-agnostic verification abstraction — RISK-05 (issue #50).
// Decouples the risk engine from any specific OTP channel (Firebase/WhatsApp/Twilio/SMS).
// Ships VerificationService with strategy interface and the MVP ManualVerificationProvider
// that marks an Order/Customer as requiring Staff confirmation — no external API calls.
// Architecture must allow WhatsAppVerificationProvider later without touching risk_engine or order logic (§18 diagram).
//
// Pure seam, no Supabase imports — tests stay offline and deterministic.
// Concrete Supabase implementation lives in lib/data/repos/verification_repository.dart
// (VerificationRepo → SupabaseVerificationRepo). ManualVerificationProvider delegates
// to that seam via dependency injection so WhatsApp provider can be swapped later.

/// Wire vocabulary for verification_requests.status.
enum VerificationStatus { pending, confirmed, rejected, expired, cancelled }

extension VerificationStatusX on VerificationStatus {
  String get wireName => switch (this) {
        VerificationStatus.pending => 'pending',
        VerificationStatus.confirmed => 'confirmed',
        VerificationStatus.rejected => 'rejected',
        VerificationStatus.expired => 'expired',
        VerificationStatus.cancelled => 'cancelled',
      };

  static VerificationStatus fromWire(String wire) => switch (wire) {
        'pending' => VerificationStatus.pending,
        'confirmed' => VerificationStatus.confirmed,
        'rejected' => VerificationStatus.rejected,
        'expired' => VerificationStatus.expired,
        'cancelled' => VerificationStatus.cancelled,
        _ => throw ArgumentError.value(wire, 'wire', 'unknown VerificationStatus'),
      };

  static VerificationStatus? tryFromWire(String? wire) {
    if (wire == null) return null;
    try {
      return fromWire(wire);
    } on ArgumentError {
      return null;
    }
  }
}

/// Immutable snapshot of a verification_requests row — provider-agnostic.
class VerificationRequest {
  const VerificationRequest({
    required this.id,
    required this.orderId,
    required this.phone,
    required this.status,
    required this.provider,
    this.expiresAt,
    this.attempts = 0,
    this.maxAttempts = 5,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String orderId;
  final String phone;
  final VerificationStatus status;
  final String provider;
  final DateTime? expiresAt;
  final int attempts;
  final int maxAttempts;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPending => status == VerificationStatus.pending;
  bool get isConfirmed => status == VerificationStatus.confirmed;
  bool get isExpired =>
      status == VerificationStatus.expired ||
      (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!.toUtc()));

  /// Parse a Supabase row (snake_case). Tolerates missing nullable fields.
  factory VerificationRequest.fromRow(Map<String, dynamic> row) {
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

    final id = (row['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) throw ArgumentError.value(row, 'row', 'VerificationRequest missing id');
    final orderId = (row['order_id'] as String? ?? row['orderId'] as String?)?.trim() ?? '';
    if (orderId.isEmpty) throw ArgumentError.value(row, 'row', 'VerificationRequest missing order_id');
    final phone = (row['phone'] as String?)?.trim() ?? '';
    if (phone.isEmpty) throw ArgumentError.value(row, 'row', 'VerificationRequest missing phone');

    final statusWire = (row['status'] as String?)?.trim() ?? 'pending';
    final status = VerificationStatusX.tryFromWire(statusWire) ?? VerificationStatus.pending;
    final provider = (row['provider'] as String?)?.trim() ?? 'manual';

    return VerificationRequest(
      id: id,
      orderId: orderId,
      phone: phone,
      status: status,
      provider: provider,
      expiresAt: parseTs(row['expires_at'] ?? row['expiresAt']),
      attempts: intFor('attempts'),
      maxAttempts: intFor('max_attempts', fallback: 5),
      createdAt: parseTs(row['created_at'] ?? row['createdAt']),
      updatedAt: parseTs(row['updated_at'] ?? row['updatedAt']),
    );
  }

  Map<String, dynamic> toRow() => {
        'id': id,
        'order_id': orderId,
        'phone': phone,
        'status': status.wireName,
        'provider': provider,
        if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
        'attempts': attempts,
        'max_attempts': maxAttempts,
        if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  VerificationRequest copyWith({
    String? id,
    String? orderId,
    String? phone,
    VerificationStatus? status,
    String? provider,
    DateTime? expiresAt,
    int? attempts,
    int? maxAttempts,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      VerificationRequest(
        id: id ?? this.id,
        orderId: orderId ?? this.orderId,
        phone: phone ?? this.phone,
        status: status ?? this.status,
        provider: provider ?? this.provider,
        expiresAt: expiresAt ?? this.expiresAt,
        attempts: attempts ?? this.attempts,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is VerificationRequest &&
      other.id == id &&
      other.orderId == orderId &&
      other.phone == phone &&
      other.status == status &&
      other.provider == provider &&
      other.expiresAt == expiresAt &&
      other.attempts == attempts &&
      other.maxAttempts == maxAttempts;

  @override
  int get hashCode => Object.hash(id, orderId, phone, status, provider, expiresAt, attempts, maxAttempts);

  @override
  String toString() => 'VerificationRequest(id:$id order:$orderId phone:$phone status:${status.wireName} provider:$provider attempts:$attempts/$maxAttempts expiresAt:$expiresAt)';
}

/// Thrown when staff/admin role check fails (42501 → VerificationPermissionException).
class VerificationPermissionException implements Exception {
  const VerificationPermissionException([this.message = 'verification: insufficient role']);
  final String message;
  @override
  String toString() => 'VerificationPermissionException: $message';
}

/// Provider strategy interface — one implementation per channel (manual, WhatsApp, SMS).
/// ManualVerificationProvider (MVP) marks Order as pending staff confirmation, no external API.
/// Future WhatsAppVerificationProvider can be added without touching risk_engine or order logic.
abstract class VerificationProvider {
  Future<VerificationRequest> requestVerification({
    required String orderId,
    required String phone,
  });

  Future<bool> verifyCode({
    required String orderId,
    required String code,
  });

  Future<void> cancelVerification({required String orderId});
}

/// Service façade — strategy holder that selects provider by name.
/// Provider-agnostic: `request(provider: 'manual')` stays decoupled from OTP channel.
abstract class VerificationService {
  Future<VerificationRequest> request({
    required String orderId,
    required String phone,
    String provider = 'manual',
  });

  Future<bool> verify({
    required String orderId,
    required String code,
  });

  Future<void> confirmByStaff({required String orderId});

  Future<void> rejectByStaff({required String orderId});
}

// ---------------------------------------------------------------------------
// Manual provider — MVP, no external API
// Creates verification_requests(status='pending', provider='manual',
// expires_at=now()+ interval '15 minutes') configurable via risk.verification_expiry_minutes
// Staff confirmByStaff sets status='confirmed' and emits risk_events(VERIFICATION_CONFIRMED) via trigger,
// rejectByStaff sets rejected and emits VERIFICATION_REJECTED. Implemented via repo seam
// so no Supabase import here (pure). The repo is injected — WhatsApp provider will reuse same seam.
// ---------------------------------------------------------------------------

/// Minimal repo seam used by ManualVerificationProvider — defined here to keep
/// domain pure (no import of data layer). The data layer's SupabaseVerificationRepo
/// implements this interface via adapter; tests use FakeVerificationRepo.
abstract class VerificationRepoForProvider {
  Future<VerificationRequest> requestVerification({
    required String orderId,
    required String phone,
    String provider = 'manual',
    String? deviceId,
  });

  Future<bool> verifyCode({
    required String orderId,
    required String code,
  });

  Future<void> cancelVerification({required String orderId});

  Future<void> confirmByStaff({required String orderId});

  Future<void> rejectByStaff({required String orderId});
}

/// MVP provider — no OTP, just creates pending row for staff to confirm/reject.
class ManualVerificationProvider implements VerificationProvider {
  ManualVerificationProvider(this._repo);

  final VerificationRepoForProvider _repo;

  @override
  Future<VerificationRequest> requestVerification({
    required String orderId,
    required String phone,
  }) =>
      _repo.requestVerification(orderId: orderId, phone: phone, provider: 'manual');

  @override
  Future<bool> verifyCode({
    required String orderId,
    required String code,
  }) =>
      // Manual has no code — always false until staff confirms (spec)
      // Delegates to repo which will compare placeholder hash and return false
      _repo.verifyCode(orderId: orderId, code: code);

  @override
  Future<void> cancelVerification({required String orderId}) =>
      _repo.cancelVerification(orderId: orderId);
}

/// Default service — holds provider map and staff delegation.
/// Staff confirm/reject delegate to repo (SECURITY DEFINER RPC with role check).
class VerificationServiceImpl implements VerificationService {
  VerificationServiceImpl({
    required Map<String, VerificationProvider> providers,
    required this._repo,
    this._fallback,
  }) : _providers = Map.unmodifiable(providers);

  final Map<String, VerificationProvider> _providers;
  final VerificationRepoForProvider _repo;
  final VerificationProvider? _fallback;

  VerificationProvider _providerFor(String provider) {
    final p = _providers[provider] ?? _fallback;
    if (p != null) return p;
    // No silent fallback to manual — typo like 'whattsapp' must surface immediately
    // rather than creating a manual row and hiding mis-configuration.
    throw ArgumentError.value(
      provider,
      'provider',
      'unknown verification provider (registered: ${_providers.keys.join(',')})',
    );
  }

  @override
  Future<VerificationRequest> request({
    required String orderId,
    required String phone,
    String provider = 'manual',
  }) =>
      _providerFor(provider).requestVerification(orderId: orderId, phone: phone);

  /// Verify is intentionally repo-centralized (hash compare via pgcrypto).
  /// Providers are request-only (create pending row); verification is provider-agnostic
  /// code_hash check in 0024, so WhatsAppVerificationProvider reuses same table and
  /// verify path without touching risk_engine. If future provider needs external OTP
  /// validation, extend here to lookup provider by order_id and delegate.
  @override
  Future<bool> verify({
    required String orderId,
    required String code,
  }) =>
      _repo.verifyCode(orderId: orderId, code: code);

  @override
  Future<void> confirmByStaff({required String orderId}) =>
      _repo.confirmByStaff(orderId: orderId);

  @override
  Future<void> rejectByStaff({required String orderId}) =>
      _repo.rejectByStaff(orderId: orderId);
}
