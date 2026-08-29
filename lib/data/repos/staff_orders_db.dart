// Staff orders DB seam (ARCH-02 split): abstract Supabase surface + typed
// RLS mapping. The repository depends on this seam so unit tests inject
// fakes and never touch the network; Postgres 42501 surfaces as a typed
// [StaffPermissionException].

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/order_status_flow.dart';
import '../adapters/supabase_phone_stamp_service.dart';
import 'staff_orders_models.dart' show staffBoardPageLimit;
import 'staff_orders_pure.dart' show orderEventInsertRow, transitionOrderPatch;

// ---------------------------------------------------------------------------
// Typed RLS error
// ---------------------------------------------------------------------------

/// RLS denied the write/read: the signed-in Google user's `profiles.role`
/// is not staff/admin (the Flutter role switcher only picks the shell).
class StaffPermissionException implements Exception {
  const StaffPermissionException();

  @override
  String toString() => 'StaffPermissionException: role not elevated';
}

/// Postgrest → typed errors: 42501 (RLS violation) becomes
/// [StaffPermissionException]; everything else propagates untouched.
Never rethrowAsTyped(PostgrestException error) {
  if (error.code == '42501') throw const StaffPermissionException();
  throw error;
}

// ---------------------------------------------------------------------------
// Database seam — abstract enough for fakes, thin adapter for Supabase
// ---------------------------------------------------------------------------

abstract class StaffOrdersDb {
  /// Calls the `staff_apply_stamp` security-definer RPC (migration 0004).
  /// Returns its boolean; null when the call itself failed.
  Future<bool?> applyStampRpc(String phone, int spend);

  Stream<List<Map<String, dynamic>>> watchOrders();

  /// `orders.phone` column of the newest board page (≤ [staffBoardPageLimit]
  /// rows) — bounded input for the name-map fetch (audit #5: never pull the
  /// whole `customers` table).
  Future<List<Map<String, dynamic>>> fetchPagePhones();

  /// `customers where phone in [phones]` (PostgREST `in.(...)`) — targeted
  /// name lookup for exactly the phones on the board page.
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(
    Set<String> phones,
  );

  Future<List<Map<String, dynamic>>> fetchAddresses(Set<String> ids);

  Future<void> updateOrder(String orderId, Map<String, dynamic> patch);

  Future<void> insertOrderEvent(Map<String, dynamic> row);

  /// Atomic RPC: update orders + insert order_events in one transaction
  /// (CORRECTNESS-03). Default impl falls back to two calls for fakes.
  Future<void> transitionOrder(
    String orderId,
    String status, {
    String? rejectReason,
    String? assignedDriverId,
    String actor = 'staff',
  }) async {
    await updateOrder(orderId, transitionOrderPatch(
      OrderWireStatus.fromWire(status) ?? OrderWireStatus.received,
      rejectReason: rejectReason,
      assignedDriverId: assignedDriverId,
    ));
    await insertOrderEvent(orderEventInsertRow(orderId,
        OrderWireStatus.fromWire(status) ?? OrderWireStatus.received));
  }

  Future<void> insertVisit(Map<String, dynamic> row);

  Future<void> insertStaffLog(Map<String, dynamic> row);

  Future<int?> fetchStampMinSpend();

  Future<int?> fetchStamps(String phone);

  Future<void> updateStamps(String phone, int stamps);

  /// Role of the signed-in Google user from `profiles` (null = no row).
  Future<String?> fetchOwnRole(String googleUserId);

  /// All driver profiles for assignment picker (user_id + display_name).
  Future<List<Map<String, dynamic>>> fetchDriverProfiles() async => const [];

  /// auth.uid() of the signed-in Google user (null when signed out).
  String? currentUserId();
}

class SupabaseStaffOrdersDb implements StaffOrdersDb {
  SupabaseStaffOrdersDb(this._client)
      : _stamp = SupabasePhoneStampService(_client),
        _phoneResolver = SupabaseCustomerPhoneResolver(_client);

  final SupabaseClient _client;
  final SupabasePhoneStampService _stamp;
  final SupabaseCustomerPhoneResolver _phoneResolver;

  @override
  Stream<List<Map<String, dynamic>>> watchOrders() {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(staffBoardPageLimit)
        .map((rows) => [
              for (final row in rows)
                Map<String, dynamic>.from(row as Map),
            ]);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPagePhones() async {
    try {
      final rows = await _client //
          .from('orders')
          .select('phone')
          .order('created_at', ascending: false)
          .limit(staffBoardPageLimit);
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(
    Set<String> phones,
  ) async {
    if (phones.isEmpty) return const [];
    try {
      return await _phoneResolver.fetchCustomersByPhones(phones);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAddresses(Set<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final rows = await _client //
          .from('addresses')
          .select('id, address_text')
          .inFilter('id', ids.toList());
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<void> updateOrder(String orderId, Map<String, dynamic> patch) async {
    try {
      await _client.from('orders').update(patch).eq('id', orderId);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<void> insertOrderEvent(Map<String, dynamic> row) async {
    try {
      await _client.from('order_events').insert(row);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<void> transitionOrder(
    String orderId,
    String status, {
    String? rejectReason,
    String? assignedDriverId,
    String actor = 'staff',
  }) async {
    try {
      await _client.rpc('transition_order', params: {
        'p_order_id': orderId,
        'p_status': status,
        'p_reject_reason': rejectReason,
        'p_assigned_driver':
            assignedDriverId == null || assignedDriverId.trim().isEmpty ? null : assignedDriverId.trim(),
        'p_actor': actor,
      });
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<void> insertVisit(Map<String, dynamic> row) async {
    try {
      await _client.from('visits').insert(row);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<void> insertStaffLog(Map<String, dynamic> row) async {
    try {
      await _client.from('staff_log').insert(row);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<int?> fetchStampMinSpend() async {
    // Delegated to shared service — single source of truth.
    return _stamp.fetchStampMinSpend();
  }

  @override
  Future<int?> fetchStamps(String phone) async {
    try {
      final row = await _client
          .from('loyalty_state')
          .select('stamps')
          .eq('phone', phone)
          .maybeSingle();
      final stamps = row?['stamps'];
      return stamps is num ? stamps.toInt() : null;
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<void> updateStamps(String phone, int stamps) async {
    try {
      await _client
          .from('loyalty_state')
          .update({'stamps': stamps}).eq('phone', phone);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<bool?> applyStampRpc(String phone, int spend) async {
    return _stamp.applyStamp(phone, spend);
  }

  @override
  Future<String?> fetchOwnRole(String googleUserId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('role')
          .eq('user_id', googleUserId)
          .maybeSingle();
      return row?['role'] as String?;
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDriverProfiles() async {
    try {
      // profiles has only user_id, role, created_at (0001_init.sql) — display_name missing.
      // Select user_id only; displayName stays null and UI falls back to userId substring.
      final rows = await _client
          .from('profiles')
          .select('user_id')
          .eq('role', 'driver');
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  String? currentUserId() => _client.auth.currentUser?.id;
}
