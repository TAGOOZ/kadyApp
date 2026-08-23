// ResultSheet (#009, shared by 3-Card Match and Scratch & Win): shows the
// round outcome big (icon + Arabic label) and credits it through the shared
// loyalty seam on تمام — mirroring spinner's ResultModal pattern.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class ResultSheet extends StatelessWidget {
  const ResultSheet({
    super.key,
    required this.win,
    required this.icon,
    required this.labelAr,
    required this.winTitle,
    required this.nothingTitle,
    required this.claimButton,
    this.validChip,
    this.voucherHint,
  });

  final bool win;
  final IconData icon;
  final String labelAr;
  final String winTitle;
  final String nothingTitle;
  final String claimButton;

  /// Shown only for voucher prizes (`صالحة` + تُستخدم في الكافيه).
  final String? validChip;
  final String? voucherHint;

  /// Pops itself, then credits the outcome through [claim]. Resolves after
  /// the claim completes so callers can reset their round state.
  static Future<void> showAndClaim(
    BuildContext context, {
    required bool win,
    required IconData icon,
    required String labelAr,
    required String winTitle,
    required String nothingTitle,
    required String claimButton,
    String? validChip,
    String? voucherHint,
    required Future<void> Function() claim,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.paperWhite,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.xl24)),
      ),
      builder: (_) => ResultSheet(
        win: win,
        icon: icon,
        labelAr: labelAr,
        winTitle: winTitle,
        nothingTitle: nothingTitle,
        claimButton: claimButton,
        validChip: validChip,
        voucherHint: voucherHint,
      ),
    ).then((_) => claim());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: win ? AppColors.secondary : AppColors.outline),
            const SizedBox(height: AppSpacing.sm16),
            Text(
              win ? winTitle : nothingTitle,
              style: AppTextStyles.headlineMobile.copyWith(color: AppColors.primary),
            ),
            if (win) ...[
              const SizedBox(height: AppSpacing.xs8),
              Text(labelAr, style: AppTextStyles.titleMd, textAlign: TextAlign.center),
            ],
            if (win && validChip != null) ...[
              const SizedBox(height: AppSpacing.sm16),
              Wrap(
                spacing: AppSpacing.xs8,
                runSpacing: AppSpacing.xs8,
                alignment: WrapAlignment.center,
                children: [
                  Chip(
                    key: const Key('result-valid-chip'),
                    label: Text(validChip!),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    voucherHint ?? '',
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('game-claim'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(claimButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
