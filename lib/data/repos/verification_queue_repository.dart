// Verification queue repository — RISK-06 (issue #51).
// Realtime pending verification queue (status='pending') joined to orders + customers.
// Arabic-first RTL, Heritage Hearth tokens, Western digits 0123 in both languages §11.11.
// Phone is canonical Customer key (CONTEXT.md). Server-authoritative loyalty + risk.
// Realtime on verification_requests like staffOrdersStreamProvider (ADR-0006).
// No polling. Bounded reads (limit 50, In filter bounded).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/riverpod_retry.dart';
import '../../core/supabase/supabase_config.dart';
import '../../domain/risk_engine.dart';
import '../../domain/risk_profile.dart';
import '../../domain/verification_service.dart';

// ---------------------------------------------------------------------------
// Pure models — aggregated pending verification with order risk snapshot
// ---------------------------------------------------------------------------

class PendingVerification {
  const PendingVerification({
    required this.verificationId,
    required this.orderId,
    required this.phone,
    this.customerName,
    required this.displayNumber,
    this.totalEgp,
    required this.riskScore,
    this.riskLevel,
    this.riskAction,
    required this.riskReasons,
    this.riskEvaluatedAt,
    required this.verificationStatus,
    required this.provider,
    this.verificationCreatedAt,
    this.expiresAt,
    this.deviceId,
    this.addressId,
  });

  final String verificationId;
  final String orderId;
  final String phone;
  final String? customerName;
  final int displayNumber;
  final int? totalEgp;
  final int riskScore;
  final RiskLevel? riskLevel;
  final RiskAction? riskAction;
  final List<String> riskReasons;
  final DateTime? riskEvaluatedAt;
  final VerificationStatus verificationStatus;
  final String provider;
  final DateTime? verificationCreatedAt;
  final DateTime? expiresAt;
  final String? deviceId;
  final String? addressId;
}

class VerificationEnrichment {
  const VerificationEnrichment({
    this.riskProfile,
    this.deviceRelatedPhones = const [],
    this.addressOrdersCount = 0,
    this.addressDistinctPhones = 0,
    this.recentEvents = const [],
  });

  final RiskProfile? riskProfile;
  final List<String> deviceRelatedPhones;
  final int addressOrdersCount;
  final int addressDistinctPhones;
  bool get addressShared => addressDistinctPhones > 1;
  final List<RiskEvent> recentEvents;
}

// ---------------------------------------------------------------------------
// Seam
// ---------------------------------------------------------------------------

abstract class VerificationQueueRepo {
  Stream<List<PendingVerification>> watchPending({int limit = 50});
  Future<List<PendingVerification>> fetchPending({int limit = 50});
  Future<VerificationEnrichment> fetchEnrichment({
    required String phone,
    String? deviceId,
    String? addressId,
  });
  Future<void> ensureAccess();
}

// ---------------------------------------------------------------------------
// Supabase implementation — bounded reads, RLS 42501 → typed exception
// ---------------------------------------------------------------------------

List<String> _parseRiskReasons(Object? v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

DateTime? _parseTs(Object? v) {
  if (v is DateTime) return v.toUtc();
  if (v is String) return DateTime.tryParse(v)?.toUtc();
  return null;
}

class SupabaseVerificationQueueRepo implements VerificationQueueRepo {
  SupabaseVerificationQueueRepo(this._client);
  final SupabaseClient _client;

  void _rethrowAsPermission(Object e) {
    if (e is PostgrestException && e.code == '42501') {
      throw const VerificationPermissionException();
    }
    final msg = e.toString();
    if (msg.contains('42501') || msg.contains('insufficient role')) {
      throw const VerificationPermissionException();
    }
  }

  // Assemble pending verifications from raw verification rows by fetching
  // orders + customers in bounded parallel queries (In filter bounded ≤50).
  Future<List<PendingVerification>> _assemble(
    List<Map<String, dynamic>> verifRows, {
    int limit = 50,
  }) async {
    if (verifRows.isEmpty) return const [];
    final sliced = verifRows.length > limit ? verifRows.sublist(0, limit) : verifRows;
    final orderIds = <String>{
      for (final r in sliced) if (r['order_id'] is String) r['order_id'] as String,
    };
    final phones = <String>{
      for (final r in sliced) if (r['phone'] is String && (r['phone'] as String).isNotEmpty) r['phone'] as String,
    };

    // Parallel bounded fetches — reuse customer_lookup pattern (Future.wait)
    List<Map<String, dynamic>> orderRows = const [];
    List<Map<String, dynamic>> customerRows = const [];
    try {
      final futures = <Future<dynamic>>[];
      if (orderIds.isNotEmpty) {
        futures.add(_client
            .from('orders')
            .select('id, display_number, phone, total, risk_score, risk_level, risk_action, risk_reasons, risk_evaluated_at, device_id, address_id, created_at')
            .inFilter('id', orderIds.toList()));
      } else {
        futures.add(Future.value(const []));
      }
      if (phones.isNotEmpty) {
        futures.add(_client.from('customers').select('phone, name').inFilter('phone', phones.toList()));
      } else {
        futures.add(Future.value(const []));
      }
      final results = await Future.wait(futures);
      orderRows = orderIds.isNotEmpty ? List<Map<String, dynamic>>.from(results[0] as List) : const [];
      customerRows = phones.isNotEmpty ? List<Map<String, dynamic>>.from(results[1] as List) : const [];
    } on PostgrestException catch (e) {
      _rethrowAsPermission(e);
      rethrow;
    }

    final orderMap = <String, Map<String, dynamic>>{
      for (final r in orderRows) if (r['id'] is String) r['id'] as String: r,
    };
    final customerMap = <String, String>{
      for (final r in customerRows) if (r['phone'] is String && r['name'] is String) r['phone'] as String: r['name'] as String,
    };

    final out = <PendingVerification>[];
    for (final vRow in sliced) {
      try {
        final verification = VerificationRequest.fromRow(Map<String, dynamic>.from(vRow));
        final orderId = verification.orderId;
        final orderRow = orderMap[orderId];
        final phone = verification.phone;
        final displayNumber = orderRow != null && orderRow['display_number'] is num ? (orderRow['display_number'] as num).toInt() : 0;
        // Risk fields from orders (server-authoritative)
        final riskScore = orderRow != null && orderRow['risk_score'] is num ? (orderRow['risk_score'] as num).toInt() : 0;
        final riskLevel = orderRow != null ? RiskLevelX.tryFromWire(orderRow['risk_level'] as String?) : null;
        final riskAction = orderRow != null ? RiskActionX.tryFromWire(orderRow['risk_action'] as String?) : null;
        final riskReasons = orderRow != null ? _parseRiskReasons(orderRow['risk_reasons']) : const <String>[];
        final riskEvaluatedAt = orderRow != null ? _parseTs(orderRow['risk_evaluated_at']) : null;
        final deviceId = (vRow['device_id'] as String?)?.trim().isNotEmpty == true ? vRow['device_id'] as String : orderRow?['device_id'] as String?;
        final addressId = orderRow?['address_id'] as String?;
        final totalEgp = orderRow != null && orderRow['total'] is num ? (orderRow['total'] as num).toInt() : null;

        out.add(PendingVerification(
          verificationId: verification.id,
          orderId: orderId,
          phone: phone,
          customerName: customerMap[phone],
          displayNumber: displayNumber,
          totalEgp: totalEgp,
          riskScore: riskScore,
          riskLevel: riskLevel,
          riskAction: riskAction,
          riskReasons: riskReasons,
          riskEvaluatedAt: riskEvaluatedAt,
          verificationStatus: verification.status,
          provider: verification.provider,
          verificationCreatedAt: verification.createdAt,
          expiresAt: verification.expiresAt,
          deviceId: deviceId,
          addressId: addressId,
        ));
      } catch (_) {
        // Skip malformed row instead of failing whole queue (defense in depth)
        continue;
      }
    }
    // Newest first already via created_at desc; ensure sorted
    out.sort((a, b) {
      final atA = a.verificationCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final atB = b.verificationCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return atB.compareTo(atA);
    });
    return out;
  }

  @override
  Future<List<PendingVerification>> fetchPending({int limit = 50}) async {
    try {
      final rows = await _client
          .from('verification_requests')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(limit);
      final verifRows = List<Map<String, dynamic>>.from(rows as List);
      return await _assemble(verifRows, limit: limit);
    } on PostgrestException catch (e) {
      _rethrowAsPermission(e);
      rethrow;
    }
  }

  @override
  Stream<List<PendingVerification>> watchPending({int limit = 50}) {
    // Supabase realtime stream on verification_requests — filter pending client-side,
    // newest first, limit 50, bounded enrichment (same pattern as staffOrdersStreamProvider).
    // We watch the whole table (bounded limit 100) and filter to pending to stay
    // compatible with Supabase stream .eq restrictions; still bounded because queue is small.
    final rawStream = _client
        .from('verification_requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100);

    // Use asyncMap to fetch orders/customers per emission — still bounded (≤50 In filter)
    return rawStream.asyncMap((rows) async {
      try {
        final pendingRows = rows
            .where((r) => (r['status'] as String?) == 'pending')
            .take(limit)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        // Sort newest first (stream order already desc, but ensure)
        pendingRows.sort((a, b) {
          final atA = _parseTs(a['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final atB = _parseTs(b['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return atB.compareTo(atA);
        });
        return await _assemble(pendingRows, limit: limit);
      } on PostgrestException catch (e) {
        _rethrowAsPermission(e);
        rethrow;
      }
    });
  }

  @override
  Future<VerificationEnrichment> fetchEnrichment({
    required String phone,
    String? deviceId,
    String? addressId,
  }) async {
    // Reuse customer_lookup_repository parallel-fetch pattern ( bounded )
    try {
      // Prepare futures — all bounded, no table scans
      final profileFuture = _client.from('customer_risk_profiles').select().eq('phone', phone).maybeSingle();

      Future<List<String>> deviceFuture;
      if (deviceId != null && deviceId.trim().isNotEmpty) {
        deviceFuture = _client
            .from('customer_devices')
            .select('phone')
            .eq('device_id', deviceId.trim())
            .then((rows) {
          final list = List<Map<String, dynamic>>.from(rows as List);
          final phones = <String>{
            for (final r in list) if (r['phone'] is String) r['phone'] as String,
          }.toList();
          phones.remove(phone);
          return phones;
        });
      } else {
        deviceFuture = Future.value(const <String>[]);
      }

      Future<(int, int)> addressFuture;
      if (addressId != null && addressId.trim().isNotEmpty) {
        final id = addressId.trim();
        addressFuture = Future.wait<dynamic>([
          // Use count exact for orders at address (no rows transferred)
          _client.from('orders').count(CountOption.exact).eq('address_id', id),
          // Distinct phones sharing address — bounded fetch of phones (≤100)
          _client.from('orders').select('phone').eq('address_id', id).limit(100),
        ]).then((results) {
          final count = results[0] as int;
          final rows = results[1] as List;
          final distinct = <String>{
            for (final r in List<Map<String, dynamic>>.from(rows))
              if (r['phone'] is String && (r['phone'] as String).isNotEmpty) r['phone'] as String,
          }.length;
          return (count, distinct);
        });
      } else {
        addressFuture = Future.value((0, 0));
      }

      final eventsFuture = _client
          .from('risk_events')
          .select()
          .eq('phone', phone)
          .order('created_at', ascending: false)
          .limit(5);

      final results = await Future.wait<dynamic>([
        profileFuture,
        deviceFuture,
        addressFuture,
        eventsFuture,
      ]);

      final profileRow = results[0] as Map<String, dynamic>?;
      RiskProfile? profile;
      if (profileRow != null) {
        try {
          profile = RiskProfile.fromRow(Map<String, dynamic>.from(profileRow));
        } catch (_) {
          profile = null;
        }
      }

      final devicePhones = results[1] as List<String>;
      final addressTuple = results[2] as (int, int);
      final eventRows = results[3] as List;

      final events = <RiskEvent>[];
      for (final r in List<Map<String, dynamic>>.from(eventRows)) {
        try {
          events.add(RiskEvent.fromRow(Map<String, dynamic>.from(r as Map)));
        } catch (_) {
          continue;
        }
      }

      return VerificationEnrichment(
        riskProfile: profile,
        deviceRelatedPhones: devicePhones,
        addressOrdersCount: addressTuple.$1,
        addressDistinctPhones: addressTuple.$2,
        recentEvents: events,
      );
    } on PostgrestException catch (e) {
      _rethrowAsPermission(e);
      rethrow;
    }
  }

  @override
  Future<void> ensureAccess() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) throw const VerificationPermissionException();
    try {
      final row = await _client.from('profiles').select('role').eq('user_id', uid).maybeSingle();
      final role = row?['role'] as String?;
      if (role != 'staff' && role != 'admin') throw const VerificationPermissionException();
    } on PostgrestException catch (e) {
      _rethrowAsPermission(e);
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------
// Fake — in-memory deterministic for widget/unit tests, no network
// ---------------------------------------------------------------------------

class FakeVerificationQueueRepo implements VerificationQueueRepo {
  FakeVerificationQueueRepo({
    List<PendingVerification>? pending,
    Map<String, VerificationEnrichment>? enrichments,
    this.accessError,
  })  : _pending = pending ?? const [],
        _enrichments = enrichments ?? {};

  List<PendingVerification> _pending;
  final Map<String, VerificationEnrichment> _enrichments;
  Object? accessError;

  // Stream controller for realtime simulation — tests push via emit()
  final _controller = StreamController<List<PendingVerification>>.broadcast();
  bool _closed = false;

  void seedPending(List<PendingVerification> list) {
    _pending = List<PendingVerification>.from(list);
    if (!_closed) _controller.add(List<PendingVerification>.from(_pending));
  }

  void emitPending(List<PendingVerification> list) {
    _pending = List<PendingVerification>.from(list);
    if (!_closed) _controller.add(List<PendingVerification>.from(_pending));
  }

  void seedEnrichment(String phone, VerificationEnrichment enrichment) {
    _enrichments[phone] = enrichment;
  }

  @override
  Stream<List<PendingVerification>> watchPending({int limit = 50}) async* {
    if (accessError != null) throw accessError!;
    // Emit current synchronously then follow controller
    yield List<PendingVerification>.from(_pending.take(limit).toList());
    yield* _controller.stream.map((list) => list.take(limit).toList());
  }

  @override
  Future<List<PendingVerification>> fetchPending({int limit = 50}) async {
    if (accessError != null) throw accessError!;
    return List<PendingVerification>.from(_pending.take(limit).toList());
  }

  @override
  Future<VerificationEnrichment> fetchEnrichment({
    required String phone,
    String? deviceId,
    String? addressId,
  }) async {
    if (accessError != null) throw accessError!;
    return _enrichments[phone] ??
        VerificationEnrichment(
          riskProfile: RiskProfile(phone: phone, totalOrders: 1, failedDeliveries: 1, cancelledOrders: 0, rejectedOrders: 0),
          deviceRelatedPhones: deviceId != null && deviceId.isNotEmpty ? ['+201000000099'] : const [],
          addressOrdersCount: addressId != null && addressId.isNotEmpty ? 3 : 0,
          addressDistinctPhones: addressId != null && addressId.isNotEmpty ? 2 : 0,
          recentEvents: const [],
        );
  }

  @override
  Future<void> ensureAccess() async {
    if (accessError != null) throw accessError!;
  }

  void dispose() {
    _closed = true;
    _controller.close();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final verificationQueueRepoProvider = Provider<VerificationQueueRepo>(
  (ref) => SupabaseVerificationQueueRepo(supabase),
);

final verificationQueueProvider = StreamProvider<List<PendingVerification>>(
  (ref) => ref.watch(verificationQueueRepoProvider).watchPending(),
  retry: noAutoRetry,
);

final verificationEnrichmentProvider = FutureProvider.family<VerificationEnrichment, EnrichmentKey>(
  (ref, key) => ref.watch(verificationQueueRepoProvider).fetchEnrichment(
    phone: key.phone,
    deviceId: key.deviceId,
    addressId: key.addressId,
  ),
  retry: noAutoRetry,
);

class EnrichmentKey {
  const EnrichmentKey({required this.phone, this.deviceId, this.addressId});
  final String phone;
  final String? deviceId;
  final String? addressId;

  @override
  bool operator ==(Object other) =>
      other is EnrichmentKey && other.phone == phone && other.deviceId == deviceId && other.addressId == addressId;

  @override
  int get hashCode => Object.hash(phone, deviceId, addressId);
}

// Access gate — mirrors staffAccessProvider (has_any_role staff,admin)
final verificationAccessProvider = FutureProvider<void>(
  (ref) => ref.watch(verificationQueueRepoProvider).ensureAccess(),
  retry: noAutoRetry,
);
