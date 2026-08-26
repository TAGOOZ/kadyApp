// ignore_for_file: unused_element, use_null_aware_elements, unnecessary_cast, unnecessary_getters_setters, curly_braces_in_flow_control_structures

// Verification repository — data seam for RISK-05 provider-agnostic verification.
// Phone is the canonical Customer key (CONTEXT.md).
// Handles hashing (code_hash never plaintext — even manual uses placeholder hash),
// attempt counting, expiry check (expires_at < now() → expired), invalidation on
// success (code_hash=NULL after confirmed). Staff confirm/reject check
// has_any_role(array['staff','admin']) like staff_apply_stamp (0004).
//
// Pattern: abstract VerificationRepo → SupabaseVerificationRepo (uses RPCs + RLS)
// + FakeVerificationRepo for tests (no network). Riverpod Provider for prod.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/verification_service.dart';

// Re-export domain types for convenient import via repo barrel.
export '../../domain/verification_service.dart'
    show
        VerificationRequest,
        VerificationStatus,
        VerificationStatusX,
        VerificationPermissionException,
        ManualVerificationProvider,
        VerificationProvider,
        VerificationService,
        VerificationRepoForProvider;

/// Abstract repo — extends the provider seam with staff actions and fetch.
/// Defined here for RLS-aware Supabase adapter; domain's VerificationRepoForProvider
/// is the same shape (we alias via implements).
abstract class VerificationRepo implements VerificationRepoForProvider {
  Future<VerificationRequest?> fetchByOrderId(String orderId);
  Future<List<VerificationRequest>> fetchPendingForPhone(String phone);
}

// ---------------------------------------------------------------------------
// Supabase implementation — all writes via SECURITY DEFINER RPCs so RLS
// INSERT via SECURITY DEFINER only is enforced. SELECT uses RLS own + staff/admin.
// ---------------------------------------------------------------------------

class SupabaseVerificationRepo implements VerificationRepo {
  SupabaseVerificationRepo(this._client);
  final SupabaseClient _client;

  // Helper to map 42501 → VerificationPermissionException
  void _rethrowAsPermission(Object e) {
    if (e is PostgrestException && e.code == '42501') {
      throw const VerificationPermissionException();
    }
    // Supabase RPC error may wrap code in message
    final msg = e.toString();
    if (msg.contains('42501') || msg.contains('insufficient role')) {
      throw const VerificationPermissionException();
    }
  }

  // Removed unused _placeholderHash — server generates placeholder via
  // pgcrypto extensions.digest; Dart never stores plaintext (code_hash is
  // always server-generated). Kept for reference but not needed client-side.

  @override
  Future<VerificationRequest> requestVerification({
    required String orderId,
    required String phone,
    String provider = 'manual',
    String? deviceId,
  }) async {
    try {
      final row = await _client.rpc<dynamic>(
        'request_verification',
        params: {
          'p_order_id': orderId,
          'p_phone': phone,
          if (deviceId != null) 'p_device_id': deviceId,
          'p_provider': provider,
        },
      );

      if (row is Map) {
        return VerificationRequest.fromRow(Map<String, dynamic>.from(row as Map));
      }
      if (row is List && row.isNotEmpty && row.first is Map) {
        return VerificationRequest.fromRow(Map<String, dynamic>.from(row.first as Map));
      }
      // Fallback: fetch the pending row
      final fetched = await fetchByOrderId(orderId);
      if (fetched != null) return fetched;
      throw StateError('request_verification returned no row');
    } on PostgrestException catch (e) {
      _rethrowAsPermission(e);
      // Race: concurrent insert hit partial unique index → return existing pending (pending-only)
      if (e.code == '23505') {
        try {
          final row = await _client
              .from('verification_requests')
              .select()
              .eq('order_id', orderId)
              .eq('status', 'pending')
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (row != null) return VerificationRequest.fromRow(Map<String, dynamic>.from(row as Map));
        } catch (_) {}
        final fetched = await fetchByOrderId(orderId);
        if (fetched != null && fetched.status == VerificationStatus.pending) return fetched;
      }
      rethrow;
    } catch (e) {
      if (e is VerificationPermissionException) rethrow;
      // Network/offline fallback not applicable — surface as is
      rethrow;
    }
  }

  @override
  Future<bool> verifyCode({
    required String orderId,
    required String code,
  }) async {
    try {
      final result = await _client.rpc<dynamic>(
        'verify_verification_code',
        params: {'p_order_id': orderId, 'p_code': code},
      );
      if (result is bool) return result;
      if (result is String) return result.toLowerCase() == 'true';
      if (result is int) return result != 0;
      return false;
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const VerificationPermissionException();
      // Expected domain failures that map to "wrong code / expired" → false
      if (e.code == 'P0001' || e.code == 'P0002' || e.code == '22023') return false;
      // Network / auth / unexpected → propagate so caller can distinguish from wrong code
      rethrow;
    }
  }

  @override
  Future<void> cancelVerification({required String orderId}) async {
    try {
      await _client.rpc<dynamic>(
        'cancel_verification',
        params: {'p_order_id': orderId},
      );
    } on PostgrestException catch (e) {
      _rethrowAsPermission(e);
      rethrow;
    }
  }

  @override
  Future<void> confirmByStaff({required String orderId}) async {
    try {
      await _client.rpc<dynamic>(
        'confirm_verification',
        params: {'p_order_id': orderId},
      );
    } on PostgrestException catch (e) {
      _rethrowAsPermission(e);
      // Map domain P0001 (expired / not pending) to StateError for UI/test parity with Fake
      if (e.code == 'P0001') throw StateError(e.message);
      rethrow;
    }
  }

  @override
  Future<void> rejectByStaff({required String orderId}) async {
    try {
      await _client.rpc<dynamic>(
        'reject_verification',
        params: {'p_order_id': orderId},
      );
    } on PostgrestException catch (e) {
      _rethrowAsPermission(e);
      if (e.code == 'P0001') throw StateError(e.message);
      rethrow;
    }
  }

  @override
  Future<VerificationRequest?> fetchByOrderId(String orderId) async {
    try {
      final row = await _client
          .from('verification_requests')
          .select()
          .eq('order_id', orderId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return VerificationRequest.fromRow(Map<String, dynamic>.from(row as Map));
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const VerificationPermissionException();
      // PGRST116 (no rows) is handled via maybeSingle → null, not exception
      rethrow;
    }
  }

  @override
  Future<List<VerificationRequest>> fetchPendingForPhone(String phone) async {
    try {
      final rows = await _client
          .from('verification_requests')
          .select()
          .eq('phone', phone)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      final now = DateTime.now().toUtc();
      return [
        for (final r in List<Map<String, dynamic>>.from(rows as List))
          VerificationRequest.fromRow(r),
      ].where((req) => req.expiresAt == null || req.expiresAt!.toUtc().isAfter(now)).toList();
    } on PostgrestException catch (e) {
      if (e.code == '42501') throw const VerificationPermissionException();
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------
// Fake — in-memory, deterministic, no network. Handles hashing, attempts,
// expiry, invalidation, idempotency, and role checks for tests.
// Mirrors SQL logic in 0024 so tests stay offline.
// ---------------------------------------------------------------------------

class FakeVerificationRepo implements VerificationRepo {
  FakeVerificationRepo({
    this.expiryMinutes = 15,
    this.defaultMaxAttempts = 5,
    String? currentRole,
  }) : _currentRole = currentRole ?? 'customer';

  final int expiryMinutes;
  final int defaultMaxAttempts;

  // Simulated role for has_any_role check
  String _currentRole;
  set currentRole(String role) => _currentRole = role;
  String get currentRole => _currentRole;

  bool get _isStaffOrAdmin => _currentRole == 'staff' || _currentRole == 'admin';

  final Map<String, List<VerificationRequest>> _byOrder = {};
  final Map<String, String> _codeHashByOrder = {}; // orderId -> hash
  final Map<String, DateTime> _expiresAtByOrder = {};

  // Expose internal hash for test "plaintext never stored"
  String? codeHashFor(String orderId) => _codeHashByOrder[orderId];

  String _hash(String input) {
    // Simple deterministic hash — not cryptographic but guarantees hash != plaintext
    // Mirrors pgcrypto SHA256 hex behavior for test purposes (hash != code)
    final bytes = input.codeUnits;
    var h = 0;
    for (final b in bytes) {
      h = ((h << 5) - h) + b;
      h &= 0xFFFFFFFF;
    }
    return 'sha256_${h.toRadixString(16)}_${bytes.length}';
  }

  String _placeholderHash(String orderId) =>
      _hash('manual:$orderId:${DateTime.now().microsecondsSinceEpoch}:${_byOrder.length}');

  VerificationRequest? _latest(String orderId) {
    final list = _byOrder[orderId];
    if (list == null || list.isEmpty) return null;
    // sorted newest first
    final sorted = List<VerificationRequest>.from(list)
      ..sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    final latest = sorted.first;
    // Lazily expire if needed so fetch reflects current wall-clock
    if (latest.expiresAt != null &&
        latest.status == VerificationStatus.pending &&
        DateTime.now().toUtc().isAfter(latest.expiresAt!.toUtc())) {
      final expired = latest.copyWith(status: VerificationStatus.expired);
      _replace(orderId, latest.id, expired);
      return expired;
    }
    return latest;
  }

  void _replace(String orderId, String id, VerificationRequest updated) {
    final list = _byOrder[orderId];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == id) {
        list[i] = updated;
        return;
      }
    }
  }

  @override
  Future<VerificationRequest> requestVerification({
    required String orderId,
    required String phone,
    String provider = 'manual',
    String? deviceId,
  }) async {
    // Idempotent: if pending already exists, return it
    final existing = _latest(orderId);
    if (existing != null && existing.status == VerificationStatus.pending) {
      // Also check expiry — if expired, create new
      if (existing.expiresAt != null && DateTime.now().toUtc().isAfter(existing.expiresAt!.toUtc())) {
        final expired = existing.copyWith(status: VerificationStatus.expired);
        _replace(orderId, existing.id, expired);
      } else {
        return existing;
      }
    }

    final now = DateTime.now().toUtc();
    final expiresAt = now.add(Duration(minutes: expiryMinutes));
    final id = 'vr_${orderId}_$now';
    final req = VerificationRequest(
      id: id,
      orderId: orderId,
      phone: phone,
      status: VerificationStatus.pending,
      provider: provider,
      expiresAt: expiresAt,
      attempts: 0,
      maxAttempts: defaultMaxAttempts,
      createdAt: now,
      updatedAt: now,
    );
    _byOrder.putIfAbsent(orderId, () => []).add(req);
    _codeHashByOrder[orderId] = _placeholderHash(orderId);
    _expiresAtByOrder[orderId] = expiresAt;
    return req;
  }

  @override
  Future<bool> verifyCode({
    required String orderId,
    required String code,
  }) async {
    final req = _latest(orderId);
    if (req == null) return false;
    if (req.status == VerificationStatus.confirmed) return false; // replay
    if (req.status == VerificationStatus.rejected ||
        req.status == VerificationStatus.expired ||
        req.status == VerificationStatus.cancelled) return false;

    // Expiry check
    if (req.expiresAt != null && DateTime.now().toUtc().isAfter(req.expiresAt!.toUtc())) {
      final expired = req.copyWith(status: VerificationStatus.expired);
      _replace(orderId, req.id, expired);
      return false;
    }

    if (req.attempts >= req.maxAttempts) {
      final expired = req.copyWith(status: VerificationStatus.expired);
      _replace(orderId, req.id, expired);
      return false;
    }

    final hash = _hash(code);
    final stored = _codeHashByOrder[orderId];

    if (stored != null && stored == hash) {
      // Success — invalidate code_hash=NULL after confirmed (spec)
      final confirmed = req.copyWith(
        status: VerificationStatus.confirmed,
        attempts: req.attempts + 1,
        updatedAt: DateTime.now().toUtc(),
      );
      _replace(orderId, req.id, confirmed);
      _codeHashByOrder[orderId] = ''; // represents NULL
      // In real SQL, orders.risk_action flips to approved — we simulate via side effect map if needed
      // For tests we just return true; service layer will handle.
      return true;
    } else {
      // Wrong code → increment attempts
      final updated = req.copyWith(
        attempts: req.attempts + 1,
        updatedAt: DateTime.now().toUtc(),
      );
      var finalReq = updated;
      if (updated.attempts >= updated.maxAttempts) {
        finalReq = updated.copyWith(status: VerificationStatus.expired);
      }
      _replace(orderId, req.id, finalReq);
      return false;
    }
  }

  @override
  Future<void> cancelVerification({required String orderId}) async {
    final req = _latest(orderId);
    if (req == null) return;
    if (req.status != VerificationStatus.pending) return;
    final cancelled = req.copyWith(status: VerificationStatus.cancelled, updatedAt: DateTime.now().toUtc());
    _replace(orderId, req.id, cancelled);
  }

  @override
  Future<void> confirmByStaff({required String orderId}) async {
    if (!_isStaffOrAdmin) throw const VerificationPermissionException();
    final req = _latest(orderId);
    if (req == null) {
      // No verification row but order may still be needs_verification — treat as success (idempotent)
      // For fake, we simulate by creating a confirmed row if not exists? But spec says confirmByStaff
      // should flip risk_action even if no pending? We'll require pending, else throw.
      throw StateError('verification: order $orderId not found');
    }
    if (req.status == VerificationStatus.confirmed) return; // idempotent
    if (req.status == VerificationStatus.expired) {
      throw StateError('verification: request expired');
    }
    if (req.expiresAt != null && DateTime.now().toUtc().isAfter(req.expiresAt!.toUtc())) {
      final expired = req.copyWith(status: VerificationStatus.expired);
      _replace(orderId, req.id, expired);
      throw StateError('verification: request expired');
    }
    if (req.status != VerificationStatus.pending) {
      throw StateError('verification: request not pending');
    }
    final confirmed = req.copyWith(
      status: VerificationStatus.confirmed,
      updatedAt: DateTime.now().toUtc(),
    );
    _replace(orderId, req.id, confirmed);
    _codeHashByOrder[orderId] = ''; // NULL invalidation
  }

  @override
  Future<void> rejectByStaff({required String orderId}) async {
    if (!_isStaffOrAdmin) throw const VerificationPermissionException();
    final req = _latest(orderId);
    if (req == null) throw StateError('verification: order $orderId not found');
    if (req.status == VerificationStatus.rejected) return; // idempotent
    if (req.status == VerificationStatus.confirmed) throw StateError('verification: already confirmed');
    final rejected = req.copyWith(status: VerificationStatus.rejected, updatedAt: DateTime.now().toUtc());
    _replace(orderId, req.id, rejected);
    _codeHashByOrder[orderId] = '';
  }

  @override
  Future<VerificationRequest?> fetchByOrderId(String orderId) async => _latest(orderId);

  @override
  Future<List<VerificationRequest>> fetchPendingForPhone(String phone) async {
    // Lazy-expire before filtering so expired don't appear as pending in staff queue
    for (final entry in _byOrder.entries) {
      for (final r in List<VerificationRequest>.from(entry.value)) {
        if (r.phone == phone &&
            r.status == VerificationStatus.pending &&
            r.expiresAt != null &&
            DateTime.now().toUtc().isAfter(r.expiresAt!.toUtc())) {
          _replace(entry.key, r.id, r.copyWith(status: VerificationStatus.expired));
        }
      }
    }
    final all = _byOrder.values.expand((l) => l).where((r) => r.phone == phone && r.status == VerificationStatus.pending).toList();
    all.sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return all;
  }

  // Test helpers
  void seedRequest(VerificationRequest req, {String? codeHash}) {
    _byOrder.putIfAbsent(req.orderId, () => []).add(req);
    if (codeHash != null) _codeHashByOrder[req.orderId] = codeHash;
  }

  void clear() {
    _byOrder.clear();
    _codeHashByOrder.clear();
    _expiresAtByOrder.clear();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final verificationRepoProvider = Provider<VerificationRepo>(
  (ref) => SupabaseVerificationRepo(supabase),
);

// Service provider — strategy holder with manual provider (MVP)
final verificationServiceProvider = Provider<VerificationService>((ref) {
  final repo = ref.watch(verificationRepoProvider) as VerificationRepoForProvider;
  final manual = ManualVerificationProvider(repo);
  return VerificationServiceImpl(
    providers: {'manual': manual},
    repo: repo,
  );
});

// Convenience: manual provider alone (for direct injection)
final manualVerificationProvider = Provider<VerificationProvider>((ref) {
  final repo = ref.watch(verificationRepoProvider) as VerificationRepoForProvider;
  return ManualVerificationProvider(repo);
});
