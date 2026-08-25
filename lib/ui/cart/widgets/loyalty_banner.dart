// Loyalty banner (ARCH-02 split): extracted from checkout_screen.dart.

import 'package:flutter/material.dart';

import '../../../core/l10n/strings_checkout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/loyalty_rules.dart';

class LoyaltyBanner extends StatelessWidget {
  const LoyaltyBanner({
    super.key,
    required this.strings,
    required this.points,
    required this.redemption,
    required this.redeemed,
    required this.remainingPoints,
    required this.onToggleRedeem,
  });

  final CheckoutStrings strings;

  /// Earn preview for this order (after redemption discount).
  final int points;

  /// Affordable reward, or null when nothing applies (toggle hidden).
  final Redemption? redemption;
  final bool redeemed;
  final int remainingPoints;
  final ValueChanged<bool?>? onToggleRedeem;

  @override
  Widget build(BuildContext context) {
    final redemption = this.redemption;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm16),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadii.md8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('☕', style: TextStyle(fontSize: 22)),
              const SizedBox(width: AppSpacing.xs8),
              Expanded(
                child: Text(
                  strings.loyaltyBanner(points),
                  style:
                      AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (redemption != null) ...[
            const SizedBox(height: AppSpacing.xs8),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md8),
              onTap: onToggleRedeem == null
                  ? null
                  : () => onToggleRedeem!(!redeemed),
              child: Row(
                children: [
                  Checkbox(
                    value: redeemed,
                    onChanged: onToggleRedeem,
                  ),
                  Expanded(
                    child: Text(
                      strings.redeemToggle(
                        redemption.costPts,
                        strings.redemptionLabel(redemption.type),
                      ),
                      style: AppTextStyles.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (redeemed)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.lg32),
                child: Text(
                  strings.redeemRemaining(remainingPoints),
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
