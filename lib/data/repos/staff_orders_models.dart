// Staff orders models (ARCH-02 split): read models and check-in payloads.
// Pure data, no Supabase. Re-exports order_items_parser for ` StaffOrder.lines`.
import '../../domain/order_status_flow.dart';
import 'order_items_parser.dart';

export 'order_items_parser.dart' show OrderItemLine, parseItemLines, itemsSummaryLine;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Minimum spend to earn a stamp when `app_config` is unreachable.
const stampMinSpendDefaultEgp = 50; // §4/§11.8 — admin-editable fallback.
const fallbackAvgPrepMinutes = 8;

/// Board page size shared by the realtime feed and the phone→name input
/// page (§11.27 bounded reads — never an unbounded table scan).
const staffBoardPageLimit = 60;

// ---------------------------------------------------------------------------
// Check-in payloads
// ---------------------------------------------------------------------------

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
// Read models
// ---------------------------------------------------------------------------

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
    this.assignedDriver,
    this.expectedReadyAtUtc,
    this.notes,
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
  final String? assignedDriver;
  final DateTime? expectedReadyAtUtc;
  final String? notes;
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
        assignedDriver: row['assigned_driver'] as String?,
        expectedReadyAtUtc: row['expected_ready_at'] == null
            ? null
            : DateTime.parse(row['expected_ready_at'] as String),
        notes: row['notes'] as String?,
        createdAtUtc: DateTime.parse(row['created_at'] as String),
      );
}

/// Driver picker option (user_id + display_name).
class DriverOption {
  const DriverOption({required this.userId, this.displayName});

  final String userId;
  final String? displayName;
}
