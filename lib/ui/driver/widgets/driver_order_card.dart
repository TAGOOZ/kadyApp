// One assigned delivery on the driver's طلباتي tab (#014, FEATURES §7):
// identity row (#display_number + items count chip), the fixed pickup line
// (single branch), drop-off address one-liner and the cash-to-collect
// highlighted in bold orange. Tapping opens the full-screen detail route;
// all callbacks are injected so tests drive fakes.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_driver.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/driver_orders_repository.dart';

class DriverOrderCard extends StatelessWidget {
  const DriverOrderCard({
    super.key,
    required this.order,
    required this.strings,
    required this.addressText,
    required this.onOpen,
  });

  final DriverOrder order;
  final DriverStrings strings;

  /// Resolved from `addresses` via orders.address_id (map-cache provider).
  final String? addressText;
  final VoidCallback onOpen;

  String get _addressLine {
    final text = addressText?.trim() ?? '';
    if (text.isEmpty) return strings.addressMissing;
    final firstPart = text.split(RegExp(r'[,،]')).first.trim();
    return firstPart.length > 32 ? '${firstPart.substring(0, 32)}…' : firstPart;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.mdLg12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                  Chip(
                    visualDensity: VisualDensity.compact,
                    labelPadding: EdgeInsets.zero,
                    label: Text(
                      strings.itemsCount(order.lines.length),
                      style: AppTextStyles.labelMd,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs8),
              Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      strings.pickupLine,
                      style: AppTextStyles.bodySm.copyWith(
                         color: AppColors.textMuted,
                       ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _addressLine,
                      style: AppTextStyles.bodyLg.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  strings.cash(order.totalEgp ?? 0),
                  style: AppTextStyles.titleMd.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.secondary, // cash orange highlight
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// History row for the السجل tab: order number, address, Cairo HH:mm time
/// and the collected cash amount. ≥48dp tall via generous padding.
class DriverHistoryRow extends StatelessWidget {
  const DriverHistoryRow({
    super.key,
    required this.order,
    required this.strings,
    required this.timeLabel,
    required this.addressText,
  });

  final DriverOrder order;
  final DriverStrings strings;

  /// Cairo wall-clock `HH:mm` of completion (ADR-0009), Western digits.
  final String timeLabel;
  final String? addressText;

  String get _addressLine {
    final text = addressText?.trim() ?? '';
    if (text.isEmpty) return strings.addressMissing;
    final firstPart = text.split(RegExp(r'[,،]')).first.trim();
    return firstPart.length > 28 ? '${firstPart.substring(0, 28)}…' : firstPart;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs8 + 2),
      child: Row(
        children: [
          Text(
            '#${order.displayNumber}',
            style: AppTextStyles.labelMd.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.coffeeBean,
            ),
          ),
          const SizedBox(width: AppSpacing.xs8),
          Expanded(
            child: Text(
              _addressLine,
              style: AppTextStyles.bodySm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.xs8),
          Text(
            timeLabel,
            style: AppTextStyles.labelMd.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(width: AppSpacing.sm16 - 4),
          Text(
            strings.cash(order.totalEgp ?? 0).replaceAll(' كاش', ''),
            style: AppTextStyles.labelMd.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
