// Totals card (ARCH-02 split): extracted from checkout_screen.dart.

import 'package:flutter/material.dart';

import '../../../core/l10n/strings_checkout.dart';
import '../../../core/theme/app_theme.dart';

class TotalsCard extends StatelessWidget {
  const TotalsCard({
    super.key,
    required this.strings,
    required this.subtotalEgp,
    required this.feeEgp,
    required this.totalEgp,
    required this.isDelivery,
  });

  final CheckoutStrings strings;
  final int subtotalEgp;
  final int feeEgp;
  final int totalEgp;
  final bool isDelivery;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TotalsRow(label: strings.subtotalRow, value: strings.egp(subtotalEgp)),
            if (isDelivery) ...[
              const SizedBox(height: AppSpacing.xs8),
              TotalsRow(
                label: strings.deliveryFeeRow,
                value: strings.egp(feeEgp),
              ),
            ],
            const Divider(),
            TotalsRow(
              label: strings.totalRow,
              value: strings.egp(totalEgp),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class TotalsRow extends StatelessWidget {
  const TotalsRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? AppTextStyles.titleSm
        : AppTextStyles.bodyLg;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}
