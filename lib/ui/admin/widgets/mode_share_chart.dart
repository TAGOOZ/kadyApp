// Mode share chart (#015): simple horizontal bars (صالة/استلام/توصيل) drawn
// with fraction-sized Containers — no chart dependency.
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ModeShareChart extends StatelessWidget {
  const ModeShareChart({
    super.key,
    required this.counts,
    required this.labelDineIn,
    required this.labelPickup,
    required this.labelDelivery,
  });

  /// `{dine_in, pickup, delivery}` tallies over the reporting window.
  final Map<String, int> counts;
  final String labelDineIn;
  final String labelPickup;
  final String labelDelivery;

  static const _colors = {
    'dine_in': AppColors.primary,
    'pickup': AppColors.secondary,
    'delivery': AppColors.coffeeBean,
  };

  String _labelFor(String mode) => switch (mode) {
        'dine_in' => labelDineIn,
        'pickup' => labelPickup,
        _ => labelDelivery,
      };

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (sum, n) => sum + n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in const ['dine_in', 'pickup', 'delivery'])
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs8),
            child: _ModeBar(
              label: _labelFor(mode),
              color: _colors[mode]!,
              fraction: total == 0 ? 0.0 : counts[mode]! / total,
              percentLabel: total == 0
                  ? '0%'
                  : '${(counts[mode]! * 100 / total).round()}%',
            ),
          ),
      ],
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.label,
    required this.color,
    required this.fraction,
    required this.percentLabel,
  });

  final String label;
  final Color color;
  final double fraction;
  final String percentLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: AppSpacing.xs8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                height: 14,
                width: (constraints.maxWidth * fraction)
                    .clamp(0.0, constraints.maxWidth),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs8),
        SizedBox(
          width: 40,
          child: Text(
            percentLabel,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.primary,
                ),
          ),
        ),
      ],
    );
  }
}
