// Slim in-flight order strip (#005): `طلبك #NNNN — {status}`. Data comes from
// the read-only probes in order_queries.dart; the full timeline lands in #006,
// so tapping shows a coming-soon snack-bar for now.
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
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
      child: InkWell(
        borderRadius:
            const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm16,
            vertical: AppSpacing.xs8 + 2,
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, size: 18, color: Colors.white),
              const SizedBox(width: AppSpacing.xs8),
              Expanded(
                child: Text(
                  strings.activeOrder(
                    displayNumber,
                    strings.statusLabel(statusWire),
                  ),
                  style: AppTextStyles.bodySm.copyWith(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.white
                  .withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}
