// Orders status slice data layer (issue #006, ADR-0006): read-only access
// to the customer's own orders plus Supabase Realtime streams so status
// transitions appear live without polling. Sits beside — never inside —
// `orders_repository.dart` (#003 owns placement); tests inject fakes over
// the [OrderStatusRepo] seam and never touch the network.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/order_status_flow.dart';

/// One-shot history fetch cap (§11.27 bounded reads): the active list screen
/// is UI-capped anyway, so `/orders` history never downloads more than this
/// newest slice.
const ownOrdersFetchLimit = 50;

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// Read model of one `orders` row as the customer sees it.
class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.displayNumber,
    required this.modeWire,
    required this.status,
    required this.createdAtUtc,
    this.rejectReason,
    this.itemCount = 0,
    this.totalEgp,
    this.hasDriver = false,
    this.phone,
    this.addressId,
  });

  final String id;
  final int displayNumber;

  /// Raw `orders.mode` wire value (`dine_in`/`pickup`/`delivery`).
  final String modeWire;
  final OrderWireStatus status;

  /// Staff rejection note (`reject_reason`), shown on the cancelled row.
  final String? rejectReason;

  /// Summed quantities from the `items` jsonb snapshot.
  final int itemCount;
  final int? totalEgp;
  final DateTime createdAtUtc;

  /// `assigned_driver` presence gates the DriverCard (name is a v1
  /// placeholder until #007 wires driver profiles).
  final bool hasDriver;

  /// Customer phone (business key) — used for driver call handoff.
  final String? phone;

  /// Delivery address foreign key — resolved via [driverAddressTextProvider]
  /// when wiring directions.
  final String? addressId;

  FlowMode? get flowMode => FlowMode.fromWire(modeWire);

  bool get isCompleted =>
      status == OrderWireStatus.done || status == OrderWireStatus.cancelled;

  static CustomerOrder fromRow(Map<String, dynamic> row) {
    var count = 0;
    final items = row['items'];
    if (items is List) {
      for (final item in items) {
        if (item is Map && item['qty'] is num) {
          count += (item['qty'] as num).toInt();
        } else {
          count += 1;
        }
      }
    }
    return CustomerOrder(
      id: row['id'] as String,
      displayNumber: (row['display_number'] as num).toInt(),
      modeWire: row['mode'] as String? ?? '',
      status: OrderWireStatus.fromWire(row['status'] as String?) ??
          OrderWireStatus.received,
      rejectReason: row['reject_reason'] as String?,
      itemCount: count,
      totalEgp: row['total'] is num ? (row['total'] as num).toInt() : null,
      createdAtUtc: DateTime.parse(row['created_at'] as String),
      hasDriver: row['assigned_driver'] != null,
      phone: row['phone'] as String?,
      addressId: row['address_id'] as String?,
    );
  }
}

/// One `order_events` row — append-only history used to timestamp steps.
class OrderEventRow {
  const OrderEventRow({required this.statusWire, required this.atUtc});

  /// Nullable per schema; rows with a null status are ignored by callers.
  final String? statusWire;
  final DateTime atUtc;

  static OrderEventRow fromRow(Map<String, dynamic> row) => OrderEventRow(
        statusWire: row['status'] as String?,
        atUtc: DateTime.parse(row['at'] as String),
      );
}

// ---------------------------------------------------------------------------
// Repository seam + Supabase Realtime implementation (ADR-0006)
// ---------------------------------------------------------------------------

abstract class OrderStatusRepo {
  Future<List<CustomerOrder>> fetchOwnOrders(String googleUserId);

  Future<List<OrderEventRow>> fetchEvents(String orderId);

  /// Live updates for a single order; emits the full row on every change.
  Stream<CustomerOrder?> watchOrder(String orderId);

  /// Live updates for every order of one customer (list screen).
  Stream<List<CustomerOrder>> watchOwnOrders(String googleUserId);
}

class SupabaseOrderStatusRepo implements OrderStatusRepo {
  SupabaseOrderStatusRepo(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CustomerOrder>> fetchOwnOrders(String googleUserId) async {
    final rows = await _client //
        .from('orders')
        .select(
          'id, display_number, mode, status, reject_reason, items, '
          'total, assigned_driver, phone, address_id, created_at',
        )
        .eq('google_user_id', googleUserId)
        .order('created_at', ascending: false)
        .limit(ownOrdersFetchLimit);
    return [
      for (final row in List<Map<String, dynamic>>.from(rows as List))
        CustomerOrder.fromRow(row),
    ];
  }

  @override
  Future<List<OrderEventRow>> fetchEvents(String orderId) async {
    final rows = await _client //
        .from('order_events')
        .select('status, at')
        .eq('order_id', orderId)
        .order('at', ascending: true);
    return [
      for (final row in List<Map<String, dynamic>>.from(rows as List))
        OrderEventRow.fromRow(row),
    ];
  }

  @override
  Stream<CustomerOrder?> watchOrder(String orderId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .map((rows) => rows.isEmpty
            ? null
            : CustomerOrder.fromRow(
                Map<String, dynamic>.from(rows.first as Map)),
              );
  }

  @override
  Stream<List<CustomerOrder>> watchOwnOrders(String googleUserId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('google_user_id', googleUserId)
        .map((rows) => [
              for (final row in rows)
                CustomerOrder.fromRow(Map<String, dynamic>.from(row as Map)),
            ]);
  }
}

final orderStatusRepoProvider = Provider<OrderStatusRepo>(
  (ref) => SupabaseOrderStatusRepo(supabase),
);

/// List-screen realtime feed filtered by `google_user_id` (ADR-0006).
final ownOrdersStreamProvider =
    StreamProvider.family<List<CustomerOrder>, String>(
  (ref, googleUserId) =>
      ref.watch(orderStatusRepoProvider).watchOwnOrders(googleUserId),
);

/// Detail-screen realtime feed for one order id.
final watchOrderProvider = StreamProvider.family<CustomerOrder?, String>(
  (ref, orderId) => ref.watch(orderStatusRepoProvider).watchOrder(orderId),
);

/// Step timestamps from `order_events`; refreshed when the order changes.
final orderEventsProvider =
    FutureProvider.family<List<OrderEventRow>, String>(
  (ref, orderId) => ref.watch(orderStatusRepoProvider).fetchEvents(orderId),
);

/// One-shot fetch used by the confirmation screen to resolve `/orders/:id`
/// from the display number (ConfirmationArgs carries no uuid).
final ownOrdersOnceProvider =
    FutureProvider.family<List<CustomerOrder>, String>(
  (ref, googleUserId) =>
      ref.watch(orderStatusRepoProvider).fetchOwnOrders(googleUserId),
);
