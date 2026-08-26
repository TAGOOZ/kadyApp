// Staff verification queue sheet — RISK-06 (issue #51).
// Entry point for Staff to review pending verification requests (same panel
// as Admin but surfaced as a bottom sheet from the staff board). Arabic-first
// RTL, Heritage Hearth tokens only, Western digits 0123 in both languages.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_risk.dart';
import '../../../core/theme/app_theme.dart';
import '../../admin/widgets/verification_queue_panel.dart';

Future<void> showVerificationQueueSheet(
  BuildContext context, {
  required WidgetRef ref,
}) {
  final lang = ref.read(localeNotifierProvider);
  final strings = RiskStrings.of(lang);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg16)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm16, AppSpacing.xs8, AppSpacing.sm16, AppSpacing.xs8),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(
                  child: Text(
                    strings.queueTitle,
                    style: AppTextStyles.titleMd.copyWith(color: AppColors.coffeeBean),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(child: VerificationQueuePanel()),
        ],
      ),
    ),
  );
}
