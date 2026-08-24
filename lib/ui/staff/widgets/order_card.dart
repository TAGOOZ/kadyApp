// One live order on the staff board (#012, FEATURES §6.1): identity row
// (#display_number + status chip + elapsed), customer name+phone, mode badge
// with timing, items summary, and the status-dependent action set. The reject
// flow opens a reason bottom sheet before cancelling. Transitions are fully
// delegated to the [onTransition] callback so tests record calls on a fake.
import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_checkout.dart';
import '../../../core/l10n/strings_staff.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/staff_orders_repository.dart';
import '../../../domain/order_status_flow.dart';
import 'driver_assignment_sheet.dart';
import 'status_chip.dart';

typedef StaffTransition = Future<void> Function(
  OrderWireStatus toStatus, {
  String? rejectReason,
  String? assignedDriverId,
});

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.strings,
    required this.lang,
    required this.nowUtc,
    required this.onTransition,
    this.customerName,
    this.addressText,
    this.onTap,
  });

  final StaffOrder order;
  final StaffStrings strings;
  final AppLang lang;

  /// Injected clock for the elapsed chip (tests pin it).
  final DateTime nowUtc;
  final StaffTransition onTransition;

  /// Resolved from the customers map (phone business key).
  final String? customerName;

  /// Resolved from `addresses` via orders.address_id.
  final String? addressText;

  /// Optional tap for the card body (header/mode/items/total) — deliberately
  /// excludes the action buttons so their [onTransition] presses do not bubble
  /// to the detail sheet. When null the card is not tappable.
  final VoidCallback? onTap;

  String get _modeLabel => switch (order.modeWire) {
        'dine_in' => CheckoutStringsCatalog.of(lang).modeDineIn,
        'delivery' => CheckoutStringsCatalog.of(lang).modeDelivery,
        _ => CheckoutStringsCatalog.of(lang).modePickup,
      };

  String get _statusLabel => switch (order.status) {
        OrderWireStatus.received => strings.statusNew,
        OrderWireStatus.accepted => strings.statusAccepted,
        OrderWireStatus.inPrep => strings.statusInPrep,
        OrderWireStatus.ready => strings.statusReady,
        OrderWireStatus.outForDelivery => strings.statusOutForDelivery,
        OrderWireStatus.done => strings.statusDone,
        OrderWireStatus.cancelled => strings.statusCancelled,
      };

  /// Mode-specific timing: pickup slot Cairo HH:mm / dine-in table-area /
  /// delivery short address; null when there is nothing to show.
  String? get _timingLabel {
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
        final address = addressText?.trim();
        if (address == null || address.isEmpty) return null;
        final firstPart = address.split(',').first.trim();
        return firstPart.length > 28
            ? '${firstPart.substring(0, 28)}…'
            : firstPart;
      case null:
        return null;
    }
  }

  List<Widget> _actions(BuildContext context) {
    Future<void> transition(OrderWireStatus to) => onTransition(to);
    switch (order.status) {
      case OrderWireStatus.received:
        return [
          OutlinedButton.icon(
            onPressed: () => _openRejectSheet(context),
            icon: const Icon(Icons.close_outlined, size: 18),
            label: Text(strings.actionReject),
          ),
          FilledButton.icon(
            onPressed: () => transition(OrderWireStatus.accepted),
            icon: const Icon(Icons.check_outlined, size: 18),
            label: Text(strings.actionAccept),
          ),
        ];
      case OrderWireStatus.accepted:
        return [
          FilledButton.icon(
            onPressed: () => transition(OrderWireStatus.inPrep),
            icon: const Icon(Icons.local_cafe_outlined, size: 18),
            label: Text(strings.actionStartPrep),
          ),
        ];
      case OrderWireStatus.inPrep:
        return [
          FilledButton.icon(
            onPressed: () => transition(OrderWireStatus.ready),
            icon: const Icon(Icons.done_all_outlined, size: 18),
            label: Text(strings.actionMarkReady),
          ),
        ];
      case OrderWireStatus.ready:
        return [
          FilledButton.icon(
            onPressed: () async {
              if (order.modeWire == 'delivery') {
                final driverId =
                    await showDriverAssignmentSheet(context, lang);
                if (driverId == null) return;
                await onTransition(
                  OrderWireStatus.outForDelivery,
                  assignedDriverId: driverId,
                );
              } else {
                await transition(OrderWireStatus.done);
              }
            },
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
            onPressed: () => transition(OrderWireStatus.done),
            icon: const Icon(Icons.celebration_outlined, size: 18),
            label: Text(strings.actionDelivered),
          ),
        ];
      case OrderWireStatus.done:
      case OrderWireStatus.cancelled:
        return const [];
    }
  }

  Future<void> _openRejectSheet(BuildContext context) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RejectReasonSheet(strings: strings),
    );
    final trimmed = reason?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await onTransition(
      OrderWireStatus.cancelled,
      rejectReason: trimmed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkout = CheckoutStringsCatalog.of(lang);
    final timing = _timingLabel;
    final actions = _actions(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            StatusChip(status: order.status, label: _statusLabel),
            const Spacer(),
            Text(
              strings.elapsed(
                elapsedMinutesSince(order.createdAtUtc, nowUtc),
              ),
              style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.textMuted,
                ),
            ),
          ],
        ),
        if (order.expectedReadyAtUtc != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                'متوقع ${formatExpectedReadyCairo(order.expectedReadyAtUtc!)}',
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Flexible(
              child: Text(
                customerName ?? order.phone ?? '—',
                style: AppTextStyles.bodyLg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (order.phone != null && customerName != null) ...[
              const SizedBox(width: 6),
              Text(
                order.phone!,
                style: AppTextStyles.bodySm
                     .copyWith(color: AppColors.textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              labelPadding: EdgeInsets.zero,
              label: Text(_modeLabel, style: AppTextStyles.labelMd),
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
        if (order.lines.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            itemsSummaryLine(order.lines),
            style: AppTextStyles.bodySm,
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            const Spacer(),
            if (order.totalEgp != null)
              Text(
                '${order.totalEgp} ${checkout.currencySuffix}',
                style: AppTextStyles.bodyLg
                    .copyWith(fontWeight: FontWeight.w700),
              ),
          ],
        ),
        if (order.status == OrderWireStatus.cancelled &&
            (order.rejectReason ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${strings.rejectTitle}: ${order.rejectReason}',
            style: AppTextStyles.bodySm
                .copyWith(color: AppColors.error),
          ),
        ],
      ],
    );

    final tappableContent = Padding(
      padding: const EdgeInsets.all(12),
      child: content,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onTap != null)
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadii.md8),
              child: tappableContent,
            )
          else
            tappableContent,
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final action in actions) ...[
                    const SizedBox(width: AppSpacing.xs8),
                    action,
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet asking WHY the order is rejected; pops with the trimmed
/// reason (or null when dismissed/blank). [onSubmitReason] is an optional
/// side-channel for tests.
class RejectReasonSheet extends StatefulWidget {
  const RejectReasonSheet({
    super.key,
    required this.strings,
    this.onSubmitReason,
  });

  final StaffStrings strings;
  final ValueChanged<String>? onSubmitReason;

  @override
  State<RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<RejectReasonSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) return;
    widget.onSubmitReason?.call(reason);
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: AppSpacing.sm16,
        end: AppSpacing.sm16,
        top: AppSpacing.sm16,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.strings.rejectTitle, style: AppTextStyles.titleMd),
            const SizedBox(height: AppSpacing.xs8),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: widget.strings.rejectHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.xs8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel),
                ),
                const SizedBox(width: AppSpacing.xs8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed:
                      _controller.text.trim().isEmpty ? null : _submit,
                  child: Text(widget.strings.rejectConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
