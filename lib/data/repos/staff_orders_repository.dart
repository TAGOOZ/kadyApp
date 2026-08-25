// Staff orders repository (ARCH-02 split): seams + providers.
// Pure helpers live in staff_orders_pure, models in staff_orders_models,
// DB seam in staff_orders_db. This file owns the Riverpod wiring.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/order_status_flow.dart';
import 'staff_orders_db.dart';
import 'staff_orders_models.dart';
import 'staff_orders_pure.dart';

// Re-export for backward compat so `import 'staff_orders_repository.dart'`
// still provides models/pure/db symbols (admin pattern).
export 'staff_orders_db.dart' show StaffPermissionException, rethrowAsTyped, StaffOrdersDb, SupabaseStaffOrdersDb;
export 'staff_orders_models.dart';
export 'staff_orders_pure.dart';

// ---------------------------------------------------------------------------
// Repository seam + implementation
// ---------------------------------------------------------------------------

abstract class StaffOrdersRepo {
  /// Realtime feed of all visible orders, newest first (ADR-0006).
  Stream<List<StaffOrder>> streamAll();

  /// Phone → Customer name map (staff read-all policy); missing phones are
  /// simply absent and render as the phone itself. Bounded (audit #5): the
  /// input is the distinct phones off the ≤60-row board page, fetched via
  /// `in.(...)` — the full `customers` table is never downloaded.
  Future<Map<String, String>> fetchCustomerNames();

  /// Delivery target text for an `orders.address_id`.
  Future<String?> fetchAddressText(String addressId);

  /// Batched address lookup for all visible delivery orders — single
  /// in.(...) query instead of N per-card family watches (perf audit #3).
  Future<Map<String, String>> fetchAddressMap(Set<String> ids) async =>
      const {};

  /// All driver profiles for handover picker (staff/admin RLS).
  Future<List<DriverOption>> fetchDrivers() async => const [];

  /// Throws [StaffPermissionException] unless profiles.role is staff/admin.
  Future<void> ensureStaffAccess();

  /// Updates `orders.status` (+ `reject_reason` when cancelling,
  /// `assigned_driver` when handing delivery) and appends
  /// an `order_events` row with actor 'staff'.
  Future<void> transition(
    String orderId,
    OrderWireStatus toStatus, {
    String? rejectReason,
    String? assignedDriverId,
  });

  /// Sets `orders.expected_ready_at` (UTC) for the ETA slider.
  Future<void> setExpectedReadyAt(String orderId, DateTime expectedUtc);

  /// Updates `orders.notes` (staff-editable delivery notes).
  Future<void> updateNotes(String orderId, String notes);

  /// Records a walk-in Visit; attempts the loyalty stamp directly but maps
  /// any failure to [VisitRecorded.loyaltyPending] instead of failing —
  /// loyalty_state RLS is own-row only until an Edge Function lands.
  Future<VisitRecorded> registerVisit(CheckInInput input);
}

class SupabaseStaffOrdersRepo implements StaffOrdersRepo {
  SupabaseStaffOrdersRepo(this._db);

  final StaffOrdersDb _db;

  @override
  Stream<List<StaffOrder>> streamAll() {
    return _db.watchOrders().map((rows) {
      final orders = [
        for (final row in rows) StaffOrder.fromRow(row),
      ]..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
      return orders;
    });
  }

  @override
  Future<Map<String, String>> fetchCustomerNames() async {
    final phoneRows = await _db.fetchPagePhones();
    final phones = <String>{
      for (final row in phoneRows)
        if (row['phone'] is String) row['phone'] as String,
    };
    final rows = await _db.fetchCustomersByPhones(phones);
    return {
      for (final row in rows)
        if (row['phone'] is String && row['name'] is String)
          row['phone'] as String: row['name'] as String,
    };
  }

  @override
  Future<String?> fetchAddressText(String addressId) async {
    final rows = await _db.fetchAddresses({addressId});
    for (final row in rows) {
      if (row['address_text'] is String) return row['address_text'] as String;
    }
    return null;
  }

  @override
  Future<Map<String, String>> fetchAddressMap(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await _db.fetchAddresses(ids);
    return {
      for (final row in rows)
        if (row['id'] is String && row['address_text'] is String)
          row['id'] as String: row['address_text'] as String,
    };
  }

  @override
  Future<void> ensureStaffAccess() async {
    final uid = _db.currentUserId();
    // The probe needs a signed-in Google user whose profile row carries the
    // elevated role; guests can never pass.
    if (uid == null || uid.isEmpty) {
      throw const StaffPermissionException();
    }
    final role = await _db.fetchOwnRole(uid);
    if (role != 'staff' && role != 'admin') {
      throw const StaffPermissionException();
    }
  }

  @override
  Future<List<DriverOption>> fetchDrivers() async {
    final rows = await _db.fetchDriverProfiles();
    return [
      for (final row in rows)
        if (row['user_id'] is String)
          DriverOption(
            userId: row['user_id'] as String,
            displayName: row['display_name'] as String?,
          ),
    ];
  }

  @override
  Future<void> transition(
    String orderId,
    OrderWireStatus toStatus, {
    String? rejectReason,
    String? assignedDriverId,
  }) async {
    await _db.transitionOrder(
      orderId,
      toStatus.wireName,
      rejectReason: rejectReason,
      assignedDriverId: assignedDriverId,
      actor: 'staff',
    );
  }

  @override
  Future<void> setExpectedReadyAt(String orderId, DateTime expectedUtc) async {
    await _db.updateOrder(orderId, {
      'expected_ready_at': expectedUtc.toIso8601String(),
    });
  }

  @override
  Future<void> updateNotes(String orderId, String notes) async {
    await _db.updateOrder(orderId, {'notes': notes});
  }

  @override
  Future<VisitRecorded> registerVisit(CheckInInput input) async {
    // 1. The visit itself is the source of truth — permission failures here
    //    are real failures and surface typed (42501 → StaffPermissionException).
    try {
      await _db.insertVisit(checkInVisitRow(input));
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }

    // 2. Audit trail is best-effort; never block the check-in UX on it.
    try {
      await _db.insertStaffLog(checkInStaffLogRow(input));
    } catch (_) {}

    // 3. Server-authoritative stamp via `staff_apply_stamp` (migration 0004,
    //    security-definer — RLS-safe). Any failure degrades to loyaltyPending.
    var loyaltyPending = false;
    try {
      final threshold =
          await _db.fetchStampMinSpend() ?? stampMinSpendDefaultEgp;
      if (input.spendEgp >= threshold) {
        final ok = await _db.applyStampRpc(input.phone, input.spendEgp);
        loyaltyPending = ok != true;
      }
    } on Exception {
      loyaltyPending = true;
    }
    return VisitRecorded(loyaltyPending: loyaltyPending);
  }
}

final staffOrdersRepoProvider = Provider<StaffOrdersRepo>(
  (ref) => SupabaseStaffOrdersRepo(SupabaseStaffOrdersDb(supabase)),
);

/// Board-wide realtime feed (ADR-0006) — every visible order, newest first.
final staffOrdersStreamProvider =
    StreamProvider<List<StaffOrder>>((ref) {
  return ref.watch(staffOrdersRepoProvider).streamAll();
});

/// Permission gate evaluated on first load; retry re-runs the probe after
/// the owner elevates profiles.role via SQL.
final staffAccessProvider = FutureProvider<void>((ref) {
  return ref.watch(staffOrdersRepoProvider).ensureStaffAccess();
});

/// Phone → Customer-name lookup, fetched once per board mount.
final staffCustomerNamesProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.watch(staffOrdersRepoProvider).fetchCustomerNames(),
);

/// Delivery address text per `address_id`, cached per id by Riverpod family.
final staffAddressTextProvider =
    FutureProvider.family<String?, String>((ref, addressId) {
  return ref.watch(staffOrdersRepoProvider).fetchAddressText(addressId);
});

/// Batched delivery address map for the current visible orders — single
/// Supabase `in.(...)` query (audit #3). Key is comma-joined sorted ids to
/// keep Riverpod family caching stable (Set equality is identity-based).
final staffAddressMapProvider =
    FutureProvider.family<Map<String, String>, String>((ref, idsKey) {
  if (idsKey.isEmpty) return const {};
  final ids = idsKey.split(',').where((s) => s.isNotEmpty).toSet();
  return ref.watch(staffOrdersRepoProvider).fetchAddressMap(ids);
});

/// Driver list for handover picker (staff/admin RLS — profiles where role=driver).
final staffDriversProvider = FutureProvider<List<DriverOption>>((ref) {
  return ref.watch(staffOrdersRepoProvider).fetchDrivers();
});
