// Result modal (#008): shows the pre-computed prize big (icon + Arabic
// label) and credits it through the shared loyalty seam on تمام. The
// prize→grant mapping lives here so tests can drive it without the UI.
import 'package:flutter/material.dart';

import '../../../../core/l10n/strings_spinner.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/loyalty_controller.dart';
import '../../../../domain/spinner_engine.dart';

/// Applies a spin outcome via [controller] — nothing is granted for
/// [SpinPrize.nothing] (token was already consumed at spin time).
Future<void> creditSpinPrize(
  LoyaltyController controller,
  SpinPrize prize,
) =>
    switch (prize) {
      SpinPrize.points5 => controller.grantPoints(5),
      SpinPrize.points10 => controller.grantPoints(10),
      SpinPrize.toppingVoucher => controller.grantVoucher(VoucherType.freeTopping),
      SpinPrize.drinkVoucher => controller.grantVoucher(VoucherType.freeDrink),
      SpinPrize.doubleNext => controller.setDoubleNextOrder(),
      SpinPrize.nothing => Future.value(),
    };

class ResultModal extends StatelessWidget {
  const ResultModal({super.key, required this.prize, required this.strings});

  final SpinPrize prize;
  final SpinnerStrings strings;

  /// Pops itself, then credits the prize through the loyalty controller.
  static void showAndClaim(
    BuildContext context, {
    required SpinPrize prize,
    required SpinnerStrings strings,
    required LoyaltyController controller,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.paperWhite,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.xl24)),
      ),
      builder: (_) => ResultModal(prize: prize, strings: strings),
    ).then((_) => creditSpinPrize(controller, prize));
  }

  /// Displays prize without extra grant (server already granted via play_* RPC).
  static void show(
    BuildContext context, {
    required SpinPrize prize,
    required SpinnerStrings strings,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.paperWhite,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.xl24)),
      ),
      builder: (_) => ResultModal(prize: prize, strings: strings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWin = prize != SpinPrize.nothing;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              prize.icon,
              size: 64,
              color: isWin ? AppColors.secondary : AppColors.outline,
            ),
            const SizedBox(height: AppSpacing.sm16),
            Text(
              isWin ? strings.resultWinTitle : strings.resultNothingTitle,
              style: AppTextStyles.headlineMobile.copyWith(
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs8),
            Text(
              prize.labelAr,
              style: AppTextStyles.titleMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('spinner-claim'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.claimButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
