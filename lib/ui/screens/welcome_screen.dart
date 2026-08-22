import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/session_controller.dart';
import '../widgets/app_logo.dart';
import '../widgets/role_switcher_sheet.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final strings = AppStrings.of(session.lang);

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
                FilledButton(
                  onPressed: () => ref
                      .read(sessionControllerProvider.notifier)
                      .markOnboarded(),
                  child: Text(strings.demoButton),
                ),
                const SizedBox(height: AppSpacing.sm16),
                Text(
                  strings.welcomeHint,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.outline,
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
