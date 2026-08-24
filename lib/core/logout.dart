// Shared logout — wired for all roles (customer/staff/driver/admin).
// Shows the canonical ProfileStrings confirmation then clears loyalty, auth
// and session caches. Router's `redirect` owns navigation to /welcome.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_controller.dart';
import '../domain/loyalty_controller.dart';
import '../domain/session_controller.dart';
import 'l10n/app_strings.dart';
import 'l10n/strings_profile.dart';
import 'theme/app_theme.dart';

Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final lang = ref.read(localeNotifierProvider);
  final s = ProfileStringsCatalog.of(lang);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(s.logoutConfirmTitle),
      content: Text(s.logoutConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(s.cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(s.logoutTile, style: const TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  // Best-effort clear — order mirrors ProfileScreen._confirmLogout.
  try {
    ref.read(loyaltyProvider.notifier).reset();
  } catch (_) {}
  try {
    await ref.read(authControllerProvider.notifier).signOut();
  } catch (_) {}
  try {
    await ref.read(sessionControllerProvider.notifier).resetToWelcome();
  } catch (_) {}
}
