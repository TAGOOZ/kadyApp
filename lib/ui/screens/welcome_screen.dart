import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_auth.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/auth_controller.dart';
import '../../domain/session_controller.dart';
import '../widgets/app_logo.dart';
import '../widgets/role_switcher_sheet.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _signInWithGoogle(
    BuildContext context,
    WidgetRef ref,
    AuthStrings authStrings,
  ) async {
    final ok = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authStrings.googleUnavailable),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final strings = AppStrings.of(session.lang);
    final authStrings = AuthStringsCatalog.of(session.lang);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.margin20,
              vertical: AppSpacing.md24,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onLongPress: () => showRoleSwitcher(context),
                  child: const AppLogo(size: 96),
                ),
                const SizedBox(height: AppSpacing.md24),
                GestureDetector(
                  onLongPress: () => showRoleSwitcher(context),
                  child:
                      Text(strings.appName, style: AppTextStyles.headlineLg),
                ),
                const SizedBox(height: AppSpacing.xs8),
                Text(
                  strings.tagline,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLg,
                ),
                const SizedBox(height: AppSpacing.xl48),
                FilledButton.icon(
                  onPressed:
                      auth.busy ? null : () => _signInWithGoogle(
                            context,
                            ref,
                            authStrings,
                          ),
                  icon: const Icon(Icons.login_outlined),
                  label: Text(authStrings.welcomeGoogleCta),
                ),
                const SizedBox(height: AppSpacing.xs8),
                TextButton(
                  onPressed: () => ref
                      .read(authControllerProvider.notifier)
                      .continueAsGuest(),
                  child: Text(authStrings.welcomeSkip),
                ),
                const SizedBox(height: AppSpacing.sm16),
                // Demo/staff entry kept for role shells that don't use the
                // customer Google gate.
                TextButton(
                  onPressed: () => ref
                      .read(sessionControllerProvider.notifier)
                      .markOnboarded(),
                  child: Text(
                    strings.demoButton,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs8),
                Text(
                  strings.welcomeHint,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textMuted,
                    ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
