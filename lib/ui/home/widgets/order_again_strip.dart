// Order-again strip (#005 v2): surfaces the most recent completed Order on
// the home hub (Damascus/Starbucks "order again" pattern). Data comes from
// the read-only lastCompletedOrderFetcherProvider probe; hidden entirely for
// guests / first-timers / offline. Tap → /orders history.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';

/// Pure summary of an `orders.items` jsonb snapshot → `لاتيه ×2 · كوكيز`
/// (max 3 lines, same ×qty convention as staff_orders_repository.dart:93).
String orderItemsSummary(Object? itemsJson) {
  if (itemsJson is! List) return '';
  final parts = <String>[];
  for (final raw in itemsJson) {
    if (raw is! Map) continue;
    final name = (raw['name_ar'] ?? '').toString();
    if (name.isEmpty) continue;
    final qty = (raw['qty'] as num?)?.toInt() ?? 1;
    parts.add(qty <= 1 ? name : '$name ×$qty');
  }
  return parts.take(3).join(' · ');
}

class OrderAgainStrip extends StatelessWidget {
  const OrderAgainStrip({
    super.key,
    required this.order,
    required this.strings,
    required this.onTap,
  });

  /// Last completed order row `{id, display_number, items, total}`.
  final Map<String, dynamic>? order;
  final HomeStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = order;
    if (row == null) return const SizedBox.shrink();
    final displayNumber = (row['display_number'] as num?)?.toInt() ?? 0;
    final summary = orderItemsSummary(row['items']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.orderAgainTitle,
          style: AppTextStyles.titleMd.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.xs8),
        Material(
          color: AppColors.paperWhite,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.lg16)),
          child: InkWell(
            borderRadius:
                const BorderRadius.all(Radius.circular(AppRadii.lg16)),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm16),
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.all(Radius.circular(AppRadii.lg16)),
                boxShadow:
                    AppShadows.coffeeShadows(offset: const Offset(0, 4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryFixedTint,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.history_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs8 + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.lastOrder(displayNumber),
                          style: AppTextStyles.titleSm
                              .copyWith(color: AppColors.coffeeBean),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (summary.isNotEmpty)
                          Text(
                            summary,
                            style: AppTextStyles.bodySm
                                .copyWith(color: AppColors.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs8),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.outline.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
