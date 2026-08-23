// Guest-save modal — reusable component (wired to order confirmation in #003).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_auth.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/auth_controller.dart';

Future<void> showGuestSavePrompt(BuildContext context, {int points = 0}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isDismissible: true,
    builder: (_) => _GuestSaveSheet(points: points),
  );
}

class _GuestSaveSheet extends ConsumerWidget {
  const _GuestSaveSheet({required this.points});

  final int points;

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    final lang = ref.read(localeNotifierProvider);
    final strings = AuthStringsCatalog.of(lang);
    final ok = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.googleUnavailable),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = AuthStringsCatalog.of(lang);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.margin20,
          AppSpacing.sm16,
          AppSpacing.margin20,
          AppSpacing.md24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.parchment,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.emoji_food_beverage_outlined,
                  size: 44,
                  color: AppColors.coffeeBean,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm16),
            Text(
              strings.guestSaveTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMd,
            ),
            const SizedBox(height: AppSpacing.xs8),
            Text(
              strings.guestSaveBody(points),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.xs8,
              runSpacing: AppSpacing.xs8,
              children: [
                Chip(label: Text(strings.guestChipPoints)),
                Chip(label: Text(strings.guestChipStamp)),
              ],
            ),
            const SizedBox(height: AppSpacing.md24),
            FilledButton(
              onPressed: () => _signIn(context, ref),
              child: Text(strings.guestSavePrimary),
            ),
            const SizedBox(height: AppSpacing.xs8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.guestSaveSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
