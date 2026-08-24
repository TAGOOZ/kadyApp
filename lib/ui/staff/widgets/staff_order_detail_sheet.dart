// StaffOrderDetailSheet — bottom sheet for the staff board (#020,
// FEATURES §6 / G10b P2). Reuses [OrderCard] expanded state: identity row
// (#display_number + status chip + elapsed), customer name+phone, mode badge
// with timing, full items list, total and the status-dependent advance
// action wired directly to [staffOrdersRepoProvider].transition via Riverpod.
// The board opens it via [showStaffOrderDetailSheet] on card tap.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_checkout.dart';
import '../../../core/l10n/strings_staff.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/staff_orders_repository.dart';
import '../../../domain/order_status_flow.dart';
import 'order_card.dart';
import 'status_chip.dart';

/// Opens the staff order detail sheet modally. The [order], [customerName]
/// and [addressText] are forwarded straight to [StaffOrderDetailSheet] so
/// the sheet has the same resolved look-ups the board card already fetched.
Future<void> showStaffOrderDetailSheet(
  BuildContext context, {
  required StaffOrder order,
  String? customerName,
  String? addressText,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => StaffOrderDetailSheet(
      order: order,
      customerName: customerName,
      addressText: addressText,
    ),
  );
}

class StaffOrderDetailSheet extends ConsumerStatefulWidget {
  const StaffOrderDetailSheet({
    super.key,
    required this.order,
    this.customerName,
    this.addressText,
  });

  final StaffOrder order;

  /// Resolved from the customers map (phone business key).
  final String? customerName;

  /// Resolved from `addresses` via orders.address_id.
  final String? addressText;

  @override
  ConsumerState<StaffOrderDetailSheet> createState() =>
      _StaffOrderDetailSheetState();
}

class _StaffOrderDetailSheetState extends ConsumerState<StaffOrderDetailSheet> {
  bool _busy = false;

  StaffOrder get order => widget.order;

  String _modeLabel(AppLang lang) => switch (order.modeWire) {
        'dine_in' => CheckoutStringsCatalog.of(lang).modeDineIn,
        'delivery' => CheckoutStringsCatalog.of(lang).modeDelivery,
        _ => CheckoutStringsCatalog.of(lang).modePickup,
      };

  String _statusLabel(StaffStrings strings) => switch (order.status) {
        OrderWireStatus.received => strings.statusNew,
        OrderWireStatus.accepted => strings.statusAccepted,
        OrderWireStatus.inPrep => strings.statusInPrep,
        OrderWireStatus.ready => strings.statusReady,
        OrderWireStatus.outForDelivery => strings.statusOutForDelivery,
        OrderWireStatus.done => strings.statusDone,
        OrderWireStatus.cancelled => strings.statusCancelled,
      };

  String? _timingLabel(StaffStrings strings) {
    switch (order.flowMode) {
      case FlowMode.pickup:
        if (order.pickupSlotUtc == null) return strings.timingNow;
        return strings.pickupAt(
          formatPickupSlotCairo(order.pickupSlotUtc!),
        );
      case FlowMode.dineIn:
        final area = order.tableArea?.trim();
        return (area == null || area.isEmpty) ? null : area;
      case FlowMode.delivery:
        final address = widget.addressText?.trim();
        if (address == null || address.isEmpty) return null;
        final firstPart = address.split(',').first.trim();
        return firstPart.length > 28
            ? '${firstPart.substring(0, 28)}…'
            : firstPart;
      case null:
        return null;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _transition(
    OrderWireStatus to, {
    String? rejectReason,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final strings = StaffStrings.of(ref.read(localeNotifierProvider));
    try {
      await ref
          .read(staffOrdersRepoProvider)
          .transition(order.id, to, rejectReason: rejectReason);
      if (!mounted) return;
      // Keep the sheet open — realtime will push the new status; caller can
      // dismiss manually. Showing no snackbar on success matches the board
      // behaviour (no success toast, errors only).
    } on StaffPermissionException {
      if (!mounted) return;
      _showSnack(strings.lockTitle);
    } catch (_) {
      if (!mounted) return;
      _showSnack(strings.transitionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRejectSheet(StaffStrings strings) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RejectReasonSheet(strings: strings),
    );
    final trimmed = reason?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _transition(OrderWireStatus.cancelled, rejectReason: trimmed);
  }

  List<Widget> _actions(BuildContext context, StaffStrings strings) {
    switch (order.status) {
      case OrderWireStatus.received:
        return [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _openRejectSheet(strings),
            icon: const Icon(Icons.close_outlined, size: 18),
            label: Text(strings.actionReject),
          ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _transition(OrderWireStatus.accepted),
            icon: const Icon(Icons.check_outlined, size: 18),
            label: Text(strings.actionAccept),
          ),
        ];
      case OrderWireStatus.accepted:
        return [
          FilledButton.icon(
            onPressed:
                _busy ? null : () => _transition(OrderWireStatus.inPrep),
            icon: const Icon(Icons.local_cafe_outlined, size: 18),
            label: Text(strings.actionStartPrep),
          ),
        ];
      case OrderWireStatus.inPrep:
        return [
          FilledButton.icon(
            onPressed: _busy ? null : () => _transition(OrderWireStatus.ready),
            icon: const Icon(Icons.done_all_outlined, size: 18),
            label: Text(strings.actionMarkReady),
          ),
        ];
      case OrderWireStatus.ready:
        return [
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _transition(
                      order.modeWire == 'delivery'
                          ? OrderWireStatus.outForDelivery
                          : OrderWireStatus.done,
                    ),
            icon: Icon(
              order.modeWire == 'delivery'
                  ? Icons.moped_outlined
                  : Icons.room_service_outlined,
              size: 18,
            ),
            label: Text(
              order.modeWire == 'delivery'
                  ? strings.actionGiveToDriver
                  : strings.actionHandover,
            ),
          ),
        ];
      case OrderWireStatus.outForDelivery:
        return [
          FilledButton.icon(
            onPressed: _busy ? null : () => _transition(OrderWireStatus.done),
            icon: const Icon(Icons.celebration_outlined, size: 18),
            label: Text(strings.actionDelivered),
          ),
        ];
      case OrderWireStatus.done:
      case OrderWireStatus.cancelled:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = StaffStrings.of(lang);
    final checkout = CheckoutStringsCatalog.of(lang);
    final timing = _timingLabel(strings);
    final statusLabel = _statusLabel(strings);
    final modeLabel = _modeLabel(lang);
    final actions = _actions(context, strings);
    final elapsed = elapsedMinutesSince(
      order.createdAtUtc,
      DateTime.now().toUtc(),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.gutter16,
          right: AppSpacing.gutter16,
          top: AppSpacing.sm16,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle.
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outline.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm16),
              // Identity row — #NNN + status chip + elapsed.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.parchment,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '#${order.displayNumber}',
                      style: AppTextStyles.labelMd.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.coffeeBean,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs8),
                  StatusChip(status: order.status, label: statusLabel),
                  const Spacer(),
                  Text(
                    strings.elapsed(elapsed),
                    style: AppTextStyles.labelMd
                        .copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs8),
              // Customer — name + phone (phone is the canonical key §11.3).
              // Reuses OrderCard's row: name if known else phone, plus a
              // muted phone suffix when both are known so the canonical key
              // is always visible (and textContaining(phone) holds).
              Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.customerName ?? order.phone ?? '—',
                      style: AppTextStyles.bodyLg
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (order.phone != null &&
                      widget.customerName != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        order.phone!,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xs8),
              // Mode badge + timing.
              Row(
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    labelPadding: EdgeInsets.zero,
                    label: Text(modeLabel, style: AppTextStyles.labelMd),
                  ),
                  if (timing != null) ...[
                    const SizedBox(width: AppSpacing.xs8),
                    Expanded(
                      child: Text(
                        timing,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xs8),
              // Items — expanded state reuses the card's summary line
              // (single Text so textContaining finds each name exactly once).
              if (order.lines.isNotEmpty)
                Text(
                  itemsSummaryLine(order.lines),
                  style: AppTextStyles.bodySm,
                ),
              const SizedBox(height: AppSpacing.xs8),
              // Total.
              if (order.totalEgp != null)
                Row(
                  children: [
                    const Spacer(),
                    Text(
                      '${order.totalEgp} ${checkout.currencySuffix}',
                      style: AppTextStyles.bodyLg
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              // Cancellation reason when present.
              if (order.status == OrderWireStatus.cancelled &&
                  (order.rejectReason ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs8),
                Text(
                  '${strings.rejectTitle}: ${order.rejectReason}',
                  style:
                      AppTextStyles.bodySm.copyWith(color: AppColors.error),
                ),
              ],
              // Advance / reject actions via staffOrdersRepo.
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (final action in actions) ...[
                      const SizedBox(width: AppSpacing.xs8),
                      action,
                    ],
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xs8),
            ],
          ),
        ),
      ),
    );
  }
}
