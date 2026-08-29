// Admin driver assignment panel (P1-1, FEATURES §6/§7).
// Lists delivery orders that are `ready` or `out_for_delivery` and lets an
// admin (or staff) assign / reassign a driver via the staff seam
// (`staffOrdersRepoProvider.transition` with `assigned_driver`).
// Uses `staffOrdersStreamProvider` (limit 60 realtime) + `staffDriversProvider`
// (profiles where role=driver). Western digits, Arabic-first.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_admin.dart';
import '../../../core/l10n/strings_common.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/staff_orders_repository.dart';
import '../../../domain/order_status_flow.dart';
import '../../staff/widgets/driver_assignment_sheet.dart';

class DriverAssignmentPanel extends ConsumerStatefulWidget {
  const DriverAssignmentPanel({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<DriverAssignmentPanel> createState() => _DriverAssignmentPanelState();
}

class _DriverAssignmentPanelState extends ConsumerState<DriverAssignmentPanel> {
  String? _busyOrderId;

  Future<void> _assign(StaffOrder order) async {
    final lang = ref.read(localeNotifierProvider);
    final driverId = await showDriverAssignmentSheet(context, lang);
    if (driverId == null) return;
    setState(() => _busyOrderId = order.id);
    try {
      await ref.read(staffOrdersRepoProvider).transition(
            order.id,
            OrderWireStatus.outForDelivery,
            assignedDriverId: driverId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.driverAssigned)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.revertedError)),
      );
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(staffOrdersStreamProvider);
    final driversAsync = ref.watch(staffDriversProvider);

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        if (e is StaffPermissionException) {
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onAccessDenied());
          return const SizedBox.shrink();
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.strings.revertedError),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => ref.invalidate(staffOrdersStreamProvider),
                child: Text(widget.strings.retry),
              ),
            ],
          ),
        );
      },
      data: (orders) {
        final delivery = orders
            .where((o) =>
                o.modeWire == 'delivery' &&
                (o.status == OrderWireStatus.ready ||
                    o.status == OrderWireStatus.outForDelivery))
            .toList();
        if (delivery.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(staffOrdersStreamProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.sm16),
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(widget.strings.noData),
                  ),
                ),
              ],
            ),
          );
        }
        final drivers = driversAsync.value ?? const <DriverOption>[];
        final driverNameOf = {
          for (final d in drivers)
            d.userId: (d.displayName?.trim().isNotEmpty == true ? d.displayName! : d.userId.substring(0, 8)),
        };
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(staffOrdersStreamProvider);
            ref.invalidate(staffDriversProvider);
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.sm16),
            itemCount: delivery.length,
            itemBuilder: (context, index) {
              final order = delivery[index];
              final isOut = order.status == OrderWireStatus.outForDelivery;
              final statusLabel = isOut ? widget.strings.statusOutForDelivery : widget.strings.statusReady;
              final currentDriver = order.assignedDriver;
              final currentDriverLabel = currentDriver == null
                  ? widget.strings.driverHint
                  : driverNameOf[currentDriver] ?? currentDriver.substring(0, 8);
              final busy = _busyOrderId == order.id;
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.xs8),
                child: ListTile(
                  leading: Icon(
                    isOut ? Icons.moped_outlined : Icons.restaurant_outlined,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    '#${order.displayNumber} • $statusLabel',
                    style: AppTextStyles.labelMd.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.phone ?? '—',
                        style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                      ),
                      Text(
                        currentDriver == null ? widget.strings.driverHint : '${widget.strings.assignDriver}: $currentDriverLabel',
                        style: AppTextStyles.bodySm,
                      ),
                    ],
                  ),
                  trailing: FilledButton(
                    onPressed: busy ? null : () => _assign(order),
                    child: busy
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(currentDriver == null
                            ? widget.strings.assignDriver
                            : CommonStrings.of(ref.watch(localeNotifierProvider)).reassign),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
