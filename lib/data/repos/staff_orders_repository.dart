// Staff orders slice data layer (issue #012, FEATURES §6): realtime feed of
// ALL orders (RLS `orders_staff_driver_admin_read`), status transitions with
// an append-only `order_events` audit row, and dine-in Check-in registration
// (`visits` source 'checkin' + best-effort `staff_log`). The Supabase client
// sits behind the [StaffOrdersDb] seam so unit tests inject fakes and never
// touch the network; Postgres 42501 (RLS denial) surfaces as a typed
// [StaffPermissionException] until profiles.role is elevated
// (docs/SUPABASE_SETUP.md — Elevate).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/order_status_flow.dart';
import 'orders_repository.dart'; // cairoUtcOffset (ADR-0009 display)

// ---------------------------------------------------------------------------
// Errors + results
// ---------------------------------------------------------------------------

/// RLS denied the write/read: the signed-in Google user's `profiles.role`
/// is not staff/admin (the Flutter role switcher only picks the shell).
class StaffPermissionException implements Exception {
  const StaffPermissionException();

  @override
  String toString() => 'StaffPermissionException: role not elevated';
}

/// Outcome of a walk-in check-in. [loyaltyPending] means the visit was
/// recorded but the stamp could not be written directly from the client —
/// current loyalty_state RLS is own-row only, so the stamp is deferred to a
/// server-side job/Edge Function post-MVP.
class VisitRecorded {
  const VisitRecorded({required this.loyaltyPending});

  final bool loyaltyPending;
}

/// Walk-in check-in payload (FEATURES §6.2, §11.31 manual fallback).
class CheckInInput {
  const CheckInInput({
    required this.phone,
    required this.spendEgp,
    this.tableArea,
  });

  /// Canonical Customer key `+20XXXXXXXXXX` (ADR-0007), pre-validated.
  final String phone;
  final int spendEgp;

  /// Composed detail, e.g. `داخل - طاولة 12` or `تراس`.
  final String? tableArea;
}

// ---------------------------------------------------------------------------
// Read models + pure payload builders / helpers
// ---------------------------------------------------------------------------

const stampMinSpendDefaultEgp = 50; // §4/§11.8 — admin-editable fallback.
const fallbackAvgPrepMinutes = 8;

/// Board page size shared by the realtime feed and the phone→name input
/// page (§11.27 bounded reads — never an unbounded table scan).
const staffBoardPageLimit = 60;

/// One flattened line of the `orders.items` jsonb snapshot.
class OrderItemLine {
  const OrderItemLine({required this.name, required this.qty});

  final String name;
  final int qty;
}

List<OrderItemLine> parseItemLines(Object? itemsJson) {
  if (itemsJson is! List) return const [];
  return [
    for (final raw in itemsJson)
      if (raw is Map)
        OrderItemLine(
          name: (raw['name_ar'] as String?) ?? '',
          qty: raw['qty'] is num ? (raw['qty'] as num).toInt() : 1,
        ),
  ];
}

/// `لاتيه ×2 · كرواسون ×1` — items summary line for the board card.
String itemsSummaryLine(List<OrderItemLine> lines,
    {String separator = ' · '}) {
  return [
    for (final line in lines)
      line.qty <= 1 ? line.name : '${line.name} ×${line.qty}',
  ].join(separator);
}

/// Read model of one `orders` row as Staff sees it.
class StaffOrder {
  const StaffOrder({
    required this.id,
    required this.displayNumber,
    required this.modeWire,
    required this.status,
    required this.createdAtUtc,
    required this.lines,
    this.phone,
    this.rejectReason,
    this.totalEgp,
    this.tableArea,
    this.pickupSlotUtc,
    this.addressId,
  });

  final String id;
  final int displayNumber;

  /// Canonical Customer phone key — nullable per schema.
  final String? phone;

  final String modeWire;
  final OrderWireStatus status;
  final String? rejectReason;
  final List<OrderItemLine> lines;
  final int? totalEgp;

  /// Dine-in table/area tag (`طاولة 12`, `داخل`, …).
  final String? tableArea;

  /// Pickup slot stored UTC, displayed Cairo HH:mm Western digits (ADR-0009).
  final DateTime? pickupSlotUtc;
  final String? addressId;
  final DateTime createdAtUtc;

  FlowMode? get flowMode => FlowMode.fromWire(modeWire);

  static StaffOrder fromRow(Map<String, dynamic> row) => StaffOrder(
        id: row['id'] as String,
        displayNumber: (row['display_number'] as num).toInt(),
        phone: row['phone'] as String?,
        modeWire: row['mode'] as String? ?? '',
        status: OrderWireStatus.fromWire(row['status'] as String?) ??
            OrderWireStatus.received,
        rejectReason: row['reject_reason'] as String?,
        lines: parseItemLines(row['items']),
        totalEgp: row['total'] is num ? (row['total'] as num).toInt() : null,
        tableArea: row['table_area'] as String?,
        pickupSlotUtc: row['pickup_slot'] == null
            ? null
            : DateTime.parse(row['pickup_slot'] as String),
        addressId: row['address_id'] as String?,
        createdAtUtc: DateTime.parse(row['created_at'] as String),
      );
}

/// `orders.update` patch for one transition; `reject_reason` rides along only
/// when cancelling with a stated reason (#0001_init.sql vocabulary).
Map<String, dynamic> transitionOrderPatch(
  OrderWireStatus toStatus, {
  String? rejectReason,
}) {
  return {
    'status': toStatus.wireName,
    if (toStatus == OrderWireStatus.cancelled &&
        rejectReason != null &&
        rejectReason.trim().isNotEmpty)
      'reject_reason': rejectReason.trim(),
  };
}

/// Append-only audit row mirroring the update (`order_events`).
Map<String, dynamic> orderEventInsertRow(
  String orderId,
  OrderWireStatus toStatus,
) {
  return {
    'order_id': orderId,
    'status': toStatus.wireName,
    'actor': 'staff',
  };
}

/// `visits` row — source is always 'checkin' for the staff sheet.
Map<String, dynamic> checkInVisitRow(CheckInInput input) {
  return {
    'phone': input.phone,
    'source': 'checkin',
    'spend_egp': input.spendEgp,
    if (input.tableArea != null && input.tableArea!.trim().isNotEmpty)
      'table_area': input.tableArea!.trim(),
  };
}

/// Best-effort audit row in `staff_log` (#0001_init.sql §13).
Map<String, dynamic> checkInStaffLogRow(CheckInInput input) {
  return {
    'actor': 'staff',
    'action': 'checkin',
    'target_phone': input.phone,
    'detail': {
      'spend_egp': input.spendEgp,
      if (input.tableArea != null && input.tableArea!.trim().isNotEmpty)
        'table_area': input.tableArea!.trim(),
    },
  };
}

/// Whole minutes since creation, floored at 0 against clock skew.
int elapsedMinutesSince(DateTime createdAtUtc, DateTime nowUtc) {
  final minutes = nowUtc.difference(createdAtUtc).inMinutes;
  return minutes < 0 ? 0 : minutes;
}

/// Rolling mean of (now − created_at) over orders currently `in_prep`,
/// rounded; falls back when nothing is on the stove.
int averagePrepMinutes(
  List<StaffOrder> orders,
  DateTime nowUtc, {
  int fallbackMinutes = fallbackAvgPrepMinutes,
}) {
  final inPrep = orders.where((o) => o.status == OrderWireStatus.inPrep);
  if (inPrep.isEmpty) return fallbackMinutes;
  var total = 0;
  for (final order in inPrep) {
    total += elapsedMinutesSince(order.createdAtUtc, nowUtc);
  }
  return (total / inPrep.length).round();
}

/// Africa/Cairo wall clock `HH:mm` with Western digits (§11.11, ADR-0009).
String formatPickupSlotCairo(DateTime utcInstant) {
  final naiveCairo = utcInstant.add(cairoUtcOffset(utcInstant));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(naiveCairo.hour)}:${two(naiveCairo.minute)}';
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

  Future<void> insertVisit(Map<String, dynamic> row);

  Future<void> insertStaffLog(Map<String, dynamic> row);

  Future<int?> fetchStampMinSpend();

  Future<int?> fetchStamps(String phone);

  Future<void> updateStamps(String phone, int stamps);

  /// Role of the signed-in Google user from `profiles` (null = no row).
  Future<String?> fetchOwnRole(String googleUserId);

  /// auth.uid() of the signed-in Google user (null when signed out).
  String? currentUserId();
}

/// Postgrest → typed errors: 42501 (RLS violation) becomes
/// [StaffPermissionException]; everything else propagates untouched.
Never rethrowAsTyped(PostgrestException error) {
  if (error.code == '42501') throw const StaffPermissionException();
  throw error;
}

class SupabaseStaffOrdersDb implements StaffOrdersDb {
  SupabaseStaffOrdersDb(this._client);

  final SupabaseClient _client;

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
      final rows = await _client //
          .from('customers')
          .select('phone, name')
          .inFilter('phone', phones.toList());
      return List<Map<String, dynamic>>.from(rows as List);
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
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'stamp_min_spend')
          .maybeSingle();
      final value = row?['value'];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
    } on PostgrestException {
      return null; // config read hiccup → constant threshold
    }
    return null;
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
    try {
      return await _client.rpc('staff_apply_stamp',
          params: {'p_phone': phone, 'p_spend': spend});
    } catch (_) {
      return null; // network / missing fn → caller degrades to pending
    }
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
  String? currentUserId() => _client.auth.currentUser?.id;
}

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

  /// Throws [StaffPermissionException] unless profiles.role is staff/admin.
  Future<void> ensureStaffAccess();

  /// Updates `orders.status` (+ `reject_reason` when cancelling) and appends
  /// an `order_events` row with actor 'staff'.
  Future<void> transition(
    String orderId,
    OrderWireStatus toStatus, {
    String? rejectReason,
  });

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
  Future<void> transition(
    String orderId,
    OrderWireStatus toStatus, {
    String? rejectReason,
  }) async {
    await _db.updateOrder(orderId, transitionOrderPatch(
      toStatus,
      rejectReason: rejectReason,
    ));
    await _db.insertOrderEvent(orderEventInsertRow(orderId, toStatus));
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
