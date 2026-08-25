// Driver orders slice data layer (#014, FEATURES §7 & #019 identity):
// realtime feed of delivery orders currently `out_for_delivery` (ADR-0006;
// assigned to any driver MVP — the admin assignment UI lands later,
// identity from profiles.display_name via DriverOrdersRepo.fetchDriverDisplayName
// (returns null so UI can fallback to DriverStrings.driverNameStub)), the
// three-step accept → picked up → delivered progression written through the
// same `orders` store
// + append-only `order_events` audit rows (actor 'driver'),
// completed-delivery history and a Cairo-day cash summary.
// The Supabase client sits behind the [DriverOrdersDb] seam so unit tests
// inject fakes and never touch the network; Postgres 42501 (RLS denial)
// surfaces as a typed [DriverPermissionException] until profiles.role is
// elevated (docs/SUPABASE_SETUP.md — Elevate).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/order_status_flow.dart';
import 'orders_repository.dart'; // cairoUtcOffset (ADR-0009 display)
import 'staff_orders_repository.dart' as staff_repo; // shared items jsonb

// ---------------------------------------------------------------------------
// Errors + read models
// ---------------------------------------------------------------------------

/// RLS denied the write/read: the signed-in Google user's `profiles.role`
/// is not driver/admin (the Flutter role switcher only picks the shell).
class DriverPermissionException implements Exception {
  const DriverPermissionException();

  @override
  String toString() => 'DriverPermissionException: role not elevated';
}

/// One flattened line of the `orders.items` jsonb snapshot (shared shape
/// with the staff board — same jsonb contract, no duplication of parsing).
typedef OrderItemLine = staff_repo.OrderItemLine;

/// Read model of one `orders` row as the Driver sees it.
class DriverOrder {
  const DriverOrder({
    required this.id,
    required this.displayNumber,
    required this.status,
    required this.createdAtUtc,
    required this.lines,
    this.phone,
    this.totalEgp,
    this.notes,
    this.addressId,
    this.assignedDriver,
  });

  final String id;
  final int displayNumber;

  /// Canonical Customer phone key — nullable per schema.
  final String? phone;
  final OrderWireStatus status;
  final List<OrderItemLine> lines;

  /// Cash to collect on arrival — always the order total for delivery.
  final int? totalEgp;

  /// Raw checkout notes; may carry a `[REDEEMED:{type}:{cost}]` prefix that
  /// must be stripped before showing ([stripRedeemedPrefix]).
  final String? notes;
  final String? addressId;
  final String? assignedDriver;
  final DateTime createdAtUtc;

  static DriverOrder fromRow(Map<String, dynamic> row) => DriverOrder(
    id: row['id'] as String,
    displayNumber: (row['display_number'] as num).toInt(),
    phone: row['phone'] as String?,
    status:
        OrderWireStatus.fromWire(row['status'] as String?) ??
        OrderWireStatus.received,
    lines: staff_repo.parseItemLines(row['items']),
    totalEgp: row['total'] is num ? (row['total'] as num).toInt() : null,
    notes: row['notes'] as String?,
    addressId: row['address_id'] as String?,
    assignedDriver: row['assigned_driver'] as String?,
    createdAtUtc: DateTime.parse(row['created_at'] as String),
  );
}

// ---------------------------------------------------------------------------
// Pure payload builders / helpers
// ---------------------------------------------------------------------------

/// Append-only audit row mirroring the driver action (`order_events`).
/// `accept`/`picked_up` are informational events on an order whose wire
/// status stays `out_for_delivery`; delivering writes event 'done' to mirror
/// the orders.status vocabulary.
Map<String, dynamic> driverOrderEventRow(String orderId, String statusWire) {
  return {'order_id': orderId, 'status': statusWire, 'actor': 'driver'};
}

/// Checkout notes may open with `[REDEEMED:{type}:{cost}] ` (reward
/// redemption riding in the notes field) — customers don't need to see it on
/// the driver's screen. Returns the trimmed remainder ('' for null/blank).
String stripRedeemedPrefix(String? notes) {
  if (notes == null) return '';
  var text = notes.trim();
  final match = RegExp(r'^\[REDEEMED:[^\]]*\]\s*').firstMatch(text);
  if (match != null) text = text.substring(match.end).trim();
  return text;
}

/// Google Maps directions handoff WITHOUT url_launcher (#014 slice): the URL
/// is copied to the clipboard and confirmed via snackbar. Arabic addresses
/// percent-encode cleanly via [Uri.encodeComponent].
String buildMapsUrl(String address) {
  return 'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeComponent(address)}';
}

/// The three driver steps in order; labels are localized in the UI layer.
enum DriverStep { accepted, pickedUp, delivered }

/// Highest step reached for one delivery, derived from the append-only
/// events (plus the terminal `done` wire status). Returns null before the
/// accept tap — nothing is done yet.
DriverStep? driverProgressFrom(
  OrderWireStatus orderStatus,
  List<String> eventStatuses,
) {
  if (orderStatus == OrderWireStatus.done) return DriverStep.delivered;
  DriverStep? step;
  for (final wire in eventStatuses) {
    switch (wire) {
      case 'accepted':
        step ??= DriverStep.accepted;
      case 'picked_up':
        step = DriverStep.pickedUp;
      case 'done':
        step = DriverStep.delivered;
    }
  }
  return step;
}

/// Cairo-day rollup of completed deliveries: count + collected cash sum
/// (ADR-0009 — stored UTC, "today" evaluated on the Cairo wall clock).
class DeliveryDaySummary {
  const DeliveryDaySummary({
    required this.deliveries,
    required this.collectedEgp,
  });

  final int deliveries;
  final int collectedEgp;
}

DeliveryDaySummary todayDeliverySummary(
  List<DriverOrder> history,
  DateTime nowUtc,
) {
  final cairoNow = nowUtc.add(cairoUtcOffset(nowUtc));
  var count = 0;
  var total = 0;
  for (final order in history) {
    final local = order.createdAtUtc.add(cairoUtcOffset(order.createdAtUtc));
    final sameCairoDay =
        local.year == cairoNow.year &&
        local.month == cairoNow.month &&
        local.day == cairoNow.day;
    if (sameCairoDay) {
      count++;
      total += order.totalEgp ?? 0;
    }
  }
  return DeliveryDaySummary(deliveries: count, collectedEgp: total);
}

// ---------------------------------------------------------------------------
// Database seam — abstract enough for fakes, thin adapter for Supabase
// ---------------------------------------------------------------------------

abstract class DriverOrdersDb {
  /// Realtime feed of delivery orders out for delivery (ADR-0006).
  Stream<List<Map<String, dynamic>>> watchAssigned();

  /// Last 50 done deliveries, newest first.
  Future<List<Map<String, dynamic>>> fetchDoneDeliveries();

  /// Delivery target text for `orders.address_id` values (map-cache).
  Future<List<Map<String, dynamic>>> fetchAddresses(Set<String> ids);

  Future<void> updateOrder(String orderId, Map<String, dynamic> patch);

  Future<void> insertOrderEvent(Map<String, dynamic> row);

  Future<void> transitionOrder(
    String orderId,
    String status, {
    String? actor,
  }) async {
    await updateOrder(orderId, {'status': status});
    await insertOrderEvent(driverOrderEventRow(orderId, status));
  }

  /// Event status wires for one order, oldest first (stepper derivation).
  Future<List<String>> fetchEventStatuses(String orderId);

  /// Phone → Customer name map; drivers have no customers SELECT under the
  /// current SQL, so callers treat this as best-effort decoration.
  Future<List<Map<String, dynamic>>> fetchCustomers();

  /// Targeted lookup — phone in (...) for exactly the phones on screen.
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(
    Set<String> phones,
  ) async =>
      const [];

  /// Role of the signed-in Google user from `profiles` (null = no row).
  Future<String?> fetchOwnRole(String googleUserId);

  /// Driver profile row for identity (display_name + role) where
  /// user_id==auth.uid() and role==driver. Returns null when missing.
  Future<Map<String, dynamic>?> fetchDriverProfile(String userId) async =>
      null;

  /// auth.uid() of the signed-in Google user (null when signed out).
  String? currentUserId();
}

/// Postgrest → typed errors: 42501 (RLS violation) becomes
/// [DriverPermissionException]; everything else propagates untouched.
Never rethrowAsTyped(PostgrestException error) {
  if (error.code == '42501') throw const DriverPermissionException();
  throw error;
}

class SupabaseDriverOrdersDb implements DriverOrdersDb {
  SupabaseDriverOrdersDb(this._client);

  final SupabaseClient _client;

  @override
  Stream<List<Map<String, dynamic>>> watchAssigned() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('mode', 'delivery')
        .eq('status', 'out_for_delivery')
        .eq('assigned_driver', uid)
        .order('created_at', ascending: false)
        .limit(30)
        .map(
          (rows) => [
            for (final row in rows) Map<String, dynamic>.from(row as Map),
          ],
        );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDoneDeliveries() async {
    try {
      final uid = _client.auth.currentUser?.id;
      var query = _client
          .from('orders')
          .select()
          .eq('mode', 'delivery')
          .eq('status', 'done');
      if (uid != null && uid.isNotEmpty) {
        query = query.eq('assigned_driver', uid);
      } else {
        // No signed-in driver → empty history (guest must not see deliveries)
        return const [];
      }
      final rows = await query.order('created_at', ascending: false).limit(50);
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAddresses(Set<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final rows =
          await _client //
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
    String? actor,
  }) async {
    try {
      await _client.rpc('transition_order', params: {
        'p_order_id': orderId,
        'p_status': status,
        'p_reject_reason': null,
        'p_assigned_driver': null,
        'p_actor': actor ?? 'driver',
      });
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<List<String>> fetchEventStatuses(String orderId) async {
    try {
      final rows = await _client
          .from('order_events')
          .select('status')
          .eq('order_id', orderId)
          .order('at', ascending: true);
      return [
        for (final row in rows as List)
          if (row['status'] is String) row['status'] as String,
      ];
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    try {
      // Bounded read — never pull the whole customers table (perf audit #1).
      // 60 is the staff board page limit; matches max distinct phones on screen.
      final rows = await _client
          .from('customers')
          .select('phone, name')
          .limit(60);
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  /// Targeted phone→name lookup for exactly the phones on screen (audit #1
  /// follow-up). Mirrors staff's fetchCustomersByPhones — avoids the
  /// bounded-full-table fallback above when the caller already knows the
  /// distinct phones.
  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(
    Set<String> phones,
  ) async {
    if (phones.isEmpty) return const [];
    try {
      final rows = await _client
          .from('customers')
          .select('phone, name')
          .inFilter('phone', phones.toList());
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
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
  Future<Map<String, dynamic>?> fetchDriverProfile(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('display_name, role')
          .eq('user_id', userId)
          .eq('role', 'driver')
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row as Map);
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

abstract class DriverOrdersRepo {
  /// Realtime feed of delivery orders out for delivery, newest first.
  Stream<List<DriverOrder>> streamAssigned();

  /// Informational pre-pickup acceptance — appends ONLY an `order_events`
  /// row ('accepted', actor 'driver'); orders.status stays out_for_delivery.
  Future<void> accept(String orderId);

  /// Café pickup confirmation — appends event 'picked_up'; NO status change.
  Future<void> markPickedUp(String orderId);

  /// Handoff complete — flips orders.status to 'done' (customer timeline
  /// shows تم التوصيل) and appends the matching event.
  Future<void> markDelivered(String orderId);

  /// Done deliveries, newest first (limit 50). assigned_driver stays a null
  /// stub until admin assignment exists → all done delivery orders show.
  Future<List<DriverOrder>> fetchHistory();

  /// Delivery target text for an `orders.address_id`.
  Future<String?> fetchAddressText(String addressId);

  /// Batched address lookup for visible orders — single in.(...) query.
  Future<Map<String, String>> fetchAddressMap(Set<String> ids) async =>
      const {};

  /// Event status wires for one order (stepper derivation on detail mount).
  Future<List<String>> fetchEventStatuses(String orderId);

  /// Phone → Customer name map; best-effort (empty when RLS blocks it).
  Future<Map<String, String>> fetchCustomerNames();

  /// Throws [DriverPermissionException] unless profiles.role is driver/admin.
  Future<void> ensureDriverAccess();

  /// Driver display name from profiles.display_name where
  /// user_id==auth.uid() and role==driver. Returns null when missing/empty
  /// so the UI can fallback to [DriverStrings.driverNameStub].
  Future<String?> fetchDriverDisplayName() async => null;
}

class SupabaseDriverOrdersRepo implements DriverOrdersRepo {
  SupabaseDriverOrdersRepo(this._db);

  final DriverOrdersDb _db;

  @override
  Stream<List<DriverOrder>> streamAssigned() {
    final uid = _db.currentUserId();
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }
    return _db.watchAssigned().map((rows) {
      final orders = [
        for (final row in rows) DriverOrder.fromRow(row),
      ]
        ..removeWhere((o) => o.assignedDriver != uid)
        ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
      return orders;
    });
  }

  @override
  Future<void> accept(String orderId) async {
    await _db.insertOrderEvent(driverOrderEventRow(orderId, 'accepted'));
  }

  @override
  Future<void> markPickedUp(String orderId) async {
    await _db.insertOrderEvent(driverOrderEventRow(orderId, 'picked_up'));
  }

  @override
  Future<void> markDelivered(String orderId) async {
    await _db.transitionOrder(orderId, OrderWireStatus.done.wireName, actor: 'driver');
  }

  @override
  Future<List<DriverOrder>> fetchHistory() async {
    final uid = _db.currentUserId();
    if (uid == null || uid.isEmpty) return const [];
    final rows = await _db.fetchDoneDeliveries();
    final filtered = [
      for (final row in rows) DriverOrder.fromRow(row),
    ]..removeWhere((o) => o.assignedDriver != uid);
    return filtered;
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
  Future<List<String>> fetchEventStatuses(String orderId) =>
      _db.fetchEventStatuses(orderId);

  @override
  Future<Map<String, String>> fetchCustomerNames() async {
    try {
      final rows = await _db.fetchCustomers();
      return {
        for (final row in rows)
          if (row['phone'] is String && row['name'] is String)
            row['phone'] as String: row['name'] as String,
      };
    } on DriverPermissionException {
      // No customers SELECT for the driver role yet — names stay decorative.
      return const {};
    }
  }

  @override
  Future<void> ensureDriverAccess() async {
    final uid = _db.currentUserId();
    // The probe needs a signed-in Google user whose profile row carries the
    // elevated role; guests can never pass.
    if (uid == null || uid.isEmpty) {
      throw const DriverPermissionException();
    }
    final role = await _db.fetchOwnRole(uid);
    if (role != 'driver' && role != 'admin') {
      throw const DriverPermissionException();
    }
  }

  @override
  Future<String?> fetchDriverDisplayName() async {
    final uid = _db.currentUserId();
    if (uid == null || uid.isEmpty) return null;
    try {
      final row = await _db.fetchDriverProfile(uid);
      if (row == null) return null;
      final name = row['display_name'] as String?;
      if (name == null || name.trim().isEmpty) return null;
      return name.trim();
    } on DriverPermissionException {
      return null;
    }
  }
}

final driverOrdersRepoProvider = Provider<DriverOrdersRepo>(
  (ref) => SupabaseDriverOrdersRepo(SupabaseDriverOrdersDb(supabase)),
);

/// Board-wide realtime feed (ADR-0006) — deliveries out for delivery now.
final driverAssignedStreamProvider = StreamProvider<List<DriverOrder>>((ref) {
  return ref.watch(driverOrdersRepoProvider).streamAssigned();
});

/// Permission gate evaluated on first load; retry re-runs the probe after
/// the owner elevates profiles.role via SQL.
final driverAccessProvider = FutureProvider<void>((ref) {
  return ref.watch(driverOrdersRepoProvider).ensureDriverAccess();
});

/// Completed deliveries for the السجل tab (fetched once per tab visit).
final driverHistoryProvider = FutureProvider<List<DriverOrder>>((ref) {
  return ref.watch(driverOrdersRepoProvider).fetchHistory();
});

/// Delivery address text per `address_id`, cached per id by Riverpod family.
final driverAddressTextProvider = FutureProvider.family<String?, String>((
  ref,
  addressId,
) {
  return ref.watch(driverOrdersRepoProvider).fetchAddressText(addressId);
});

/// Batched address map — single in.(...) query for visible orders.
final driverAddressMapProvider =
    FutureProvider.family<Map<String, String>, String>((ref, idsKey) {
  if (idsKey.isEmpty) return const {};
  final ids = idsKey.split(',').where((s) => s.isNotEmpty).toSet();
  return ref.watch(driverOrdersRepoProvider).fetchAddressMap(ids);
});
