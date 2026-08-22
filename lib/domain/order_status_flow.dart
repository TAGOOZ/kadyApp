// Pure order-status step logic (issue #006, FEATURES §3.6): per-mode
// timeline steps, current-index lookup and cancelled terminal handling.
// No Flutter/data imports beyond IconData so it stays unit-testable;
// staff (#012) writes statuses directly — this layer only renders them.
import 'package:flutter/material.dart';

/// DB `orders.status` check-constraint vocabulary (#0001_init.sql).
enum OrderWireStatus {
  received('new'),
  accepted('accepted'),
  inPrep('in_prep'),
  ready('ready'),
  outForDelivery('out_for_delivery'),
  done('done'),
  cancelled('cancelled');

  const OrderWireStatus(this.wireName);
  final String wireName;

  static OrderWireStatus? fromWire(String? wire) {
    for (final value in OrderWireStatus.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// Service mode mirrored locally so the domain stays independent of the
/// data layer; built from the `orders.mode` wire value.
enum FlowMode {
  dineIn('dine_in'),
  pickup('pickup'),
  delivery('delivery');

  const FlowMode(this.wireName);
  final String wireName;

  static FlowMode? fromWire(String? wire) {
    for (final value in FlowMode.values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

/// One immutable timeline node; labels are pre-localized because the pure
/// layer has no access to the strings catalog.
class FlowStep {
  const FlowStep({
    required this.status,
    required this.labelAr,
    required this.labelEn,
    required this.icon,
  });

  final OrderWireStatus status;
  final String labelAr;
  final String labelEn;
  final IconData icon;
}

abstract final class OrderStatusFlow {
  /// صالة: تم الاستلام ← تم القبول ← قيد التحضير ← جاهز ← تم التقديم.
  static const _dineIn = [
    FlowStep(
      status: OrderWireStatus.received,
      labelAr: 'تم الاستلام',
      labelEn: 'Received',
      icon: Icons.receipt_long_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.accepted,
      labelAr: 'تم القبول',
      labelEn: 'Accepted',
      icon: Icons.task_alt_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.inPrep,
      labelAr: 'قيد التحضير',
      labelEn: 'In preparation',
      icon: Icons.local_cafe_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.ready,
      labelAr: 'جاهز',
      labelEn: 'Ready',
      icon: Icons.room_service_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.done,
      labelAr: 'تم التقديم',
      labelEn: 'Served',
      icon: Icons.celebration_outlined,
    ),
  ];

  /// استلام ends at جاهز للاستلام — no served/done step (§3.6).
  static const _pickup = [
    FlowStep(
      status: OrderWireStatus.received,
      labelAr: 'تم الاستلام',
      labelEn: 'Received',
      icon: Icons.receipt_long_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.accepted,
      labelAr: 'تم القبول',
      labelEn: 'Accepted',
      icon: Icons.task_alt_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.inPrep,
      labelAr: 'قيد التحضير',
      labelEn: 'In preparation',
      icon: Icons.local_cafe_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.ready,
      labelAr: 'جاهز للاستلام',
      labelEn: 'Ready for pickup',
      icon: Icons.shopping_bag_outlined,
    ),
  ];

  /// توصيل adds في الطريق إليك before تم التوصيل (§3.6).
  static const _delivery = [
    FlowStep(
      status: OrderWireStatus.received,
      labelAr: 'تم الاستلام',
      labelEn: 'Received',
      icon: Icons.receipt_long_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.accepted,
      labelAr: 'تم القبول',
      labelEn: 'Accepted',
      icon: Icons.task_alt_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.inPrep,
      labelAr: 'قيد التحضير',
      labelEn: 'In preparation',
      icon: Icons.local_cafe_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.ready,
      labelAr: 'جاهز',
      labelEn: 'Ready',
      icon: Icons.inventory_2_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.outForDelivery,
      labelAr: 'في الطريق إليك',
      labelEn: 'Out for delivery',
      icon: Icons.moped_outlined,
    ),
    FlowStep(
      status: OrderWireStatus.done,
      labelAr: 'تم التوصيل',
      labelEn: 'Delivered',
      icon: Icons.celebration_outlined,
    ),
  ];

  static List<FlowStep> stepsFor(FlowMode mode) => switch (mode) {
        FlowMode.dineIn => _dineIn,
        FlowMode.pickup => _pickup,
        FlowMode.delivery => _delivery,
      };

  /// Index of [status] inside the mode's steps; -1 for cancelled/unknown
  /// statuses (they render as the special terminal row instead).
  static int indexOfCurrent(FlowMode mode, OrderWireStatus status) {
    final steps = stepsFor(mode);
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].status == status) return i;
    }
    return -1;
  }

  /// Step matching [status], or null when not part of the mode's flow.
  static FlowStep? stepFor(FlowMode mode, OrderWireStatus status) {
    final index = indexOfCurrent(mode, status);
    return index >= 0 ? stepsFor(mode)[index] : null;
  }
}
