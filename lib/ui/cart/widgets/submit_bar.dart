// Submit bar (ARCH-02 split): extracted from checkout_screen.dart.

import 'package:flutter/material.dart';

import '../../../core/l10n/strings_checkout.dart';
import '../../../core/theme/app_theme.dart';

class SubmitBar extends StatelessWidget {
  const SubmitBar({
    super.key,
    required this.label,
    required this.totalEgp,
    required this.strings,
    required this.busy,
    required this.onSubmit,
  });

  final String label;
  final int totalEgp;
  final CheckoutStrings strings;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        boxShadow: AppShadows.coffeeShadows(
          offset: const Offset(0, -4),
          blurRadius: 12,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.margin20,
        AppSpacing.sm16,
        AppSpacing.margin20,
        AppSpacing.md24,
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('$label · ${strings.egp(totalEgp)}'),
        ),
      ),
    );
  }
}
