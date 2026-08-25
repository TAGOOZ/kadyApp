// Staff orders pure helpers (ARCH-02 split): payload builders and math.
// No Supabase, no Riverpod — unit-tested in isolation.

import '../../domain/order_status_flow.dart';
import 'orders_repository.dart' show cairoUtcOffset;
import 'staff_orders_models.dart';

// ---------------------------------------------------------------------------
// Payload builders
// ---------------------------------------------------------------------------

/// `orders.update` patch for one transition; `reject_reason` rides along only
/// when cancelling with a stated reason (#0001_init.sql vocabulary).
/// `assignedDriverId` is written when handing a delivery to a driver
/// (ready → out_for_delivery).
Map<String, dynamic> transitionOrderPatch(
  OrderWireStatus toStatus, {
  String? rejectReason,
  String? assignedDriverId,
}) {
  return {
    'status': toStatus.wireName,
    if (toStatus == OrderWireStatus.cancelled &&
        rejectReason != null &&
        rejectReason.trim().isNotEmpty)
      'reject_reason': rejectReason.trim(),
    if (assignedDriverId != null && assignedDriverId.trim().isNotEmpty)
      'assigned_driver': assignedDriverId.trim(),
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

// ---------------------------------------------------------------------------
// Time helpers
// ---------------------------------------------------------------------------

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

/// Alias for expected_ready_at display (same Cairo HH:mm).
String formatExpectedReadyCairo(DateTime utcInstant) =>
    formatPickupSlotCairo(utcInstant);
