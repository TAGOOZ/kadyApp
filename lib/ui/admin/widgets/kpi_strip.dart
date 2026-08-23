// KPI strip (#015): three stat cards under the admin header — Western digits.
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class KpiStrip extends StatelessWidget {
  const KpiStrip({
    super.key,
    required this.ordersToday,
    required this.activeCustomers,
    required this.avgBasketEgp,
    required this.labelOrdersToday,
    required this.labelActiveCustomers,
    required this.labelAvgBasket,
  });

  final int ordersToday;
  final int activeCustomers;
  final double avgBasketEgp;
  final String labelOrdersToday;
  final String labelActiveCustomers;
  final String labelAvgBasket;

  static String formatAmount(double value) =>
      value == value.roundToDouble()
          ? value.round().toString()
          : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: labelOrdersToday,
            value: ordersToday.toString(),
          ),
        ),
        const SizedBox(width: AppSpacing.xs8),
        Expanded(
          child: _KpiCard(
            label: labelActiveCustomers,
            value: activeCustomers.toString(),
          ),
        ),
        const SizedBox(width: AppSpacing.xs8),
        Expanded(
          child: _KpiCard(
            label: labelAvgBasket,
            value: formatAmount(avgBasketEgp),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs8,
          horizontal: AppSpacing.xs8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
