// In-flight order strip (#005 v2): promoted to the top of the hub with a
// leading icon medallion + trailing chevron button treatment on the filled
// deep-green surface. Data comes from the read-only probes in
// order_queries.dart; tap → /orders timeline.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';

class ActiveOrderStrip extends StatelessWidget {
  const ActiveOrderStrip({
    super.key,
    required this.orders,
    required this.strings,
    required this.onTap,
  });

  final List<Map<String, dynamic>> orders;
  final HomeStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const SizedBox.shrink();
    final order = orders.first;
    final displayNumber = (order['display_number'] as num?)?.toInt() ?? 0;
    final statusWire = (order['status'] as String?) ?? 'new';

    return Material(
      key: const Key('home_active_order_strip'),
      color: AppColors.primaryContainer,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.lg16)),
      child: InkWell(
        borderRadius:
            const BorderRadius.all(Radius.circular(AppRadii.lg16)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm16,
            vertical: AppSpacing.xs8 + 4,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.receipt_long,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSpacing.xs8 + 2),
              Expanded(
                child: Text(
                  strings.activeOrder(
                    displayNumber,
                    strings.statusLabel(statusWire),
                  ),
                  style: AppTextStyles.bodySm.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
