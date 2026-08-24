import 'package:flutter/foundation.dart';
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
      backgroundColor: AppColors.coffeeBean,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/welcome_hero.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.parchment,
                          AppColors.primaryFixedTint,
                        ],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.local_cafe,
                        size: 64,
                        color: AppColors.coffeeBean,
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.coffeeBean.withValues(alpha: 0.55),
                        AppColors.coffeeBean.withValues(alpha: 0.75),
                      ],
                      stops: const [0.4, 0.8, 1.0],
                    ),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.margin20,
                        AppSpacing.md24,
                        AppSpacing.margin20,
                        AppSpacing.lg32,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onLongPress: () {
                              if (!kDebugMode &&
                                  const String.fromEnvironment(
                                          'ENABLE_ROLE_SWITCHER') !=
                                      'true') {
                                return;
                              }
                              showRoleSwitcher(context);
                            },
                            child: const AppLogo(size: 72),
                          ),
                          const SizedBox(height: AppSpacing.sm16),
                          GestureDetector(
                            onLongPress: () {
                              if (!kDebugMode &&
                                  const String.fromEnvironment(
                                          'ENABLE_ROLE_SWITCHER') !=
                                      'true') {
                                return;
                              }
                              showRoleSwitcher(context);
                            },
                            child: Text(
                              strings.appName,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.headlineLg.copyWith(
                                color: AppColors.paperWhite,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs8),
                          Text(
                            authStrings.welcomeGreeting,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.titleSm.copyWith(
                              color: AppColors.paperWhite.withValues(alpha: 0.92),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs8),
                          Text(
                            strings.tagline,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.paperWhite.withValues(alpha: 0.78),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.paperWhite,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.xl24),
              ),
              boxShadow: AppShadows.coffeeShadows(
                offset: const Offset(0, -6),
                blurRadius: 18,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.margin20,
              AppSpacing.md24,
              AppSpacing.margin20,
              AppSpacing.lg32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  authStrings.welcomeHeadline,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleSm.copyWith(
                    color: AppColors.coffeeBean,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _Benefit(
                      icon: Icons.stars_rounded,
                      label: authStrings.benefitPoints,
                    ),
                    _Benefit(
                      icon: Icons.local_cafe_rounded,
                      label: authStrings.benefitFreeCup,
                    ),
                    _Benefit(
                      icon: Icons.sports_esports_rounded,
                      label: authStrings.benefitGames,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md24),
                SizedBox(
                  width: double.infinity,
                  child: _GoogleButton(
                    busy: auth.busy,
                    label: authStrings.welcomeGoogleCta,
                    onPressed: () => _signInWithGoogle(context, ref, authStrings),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs8),
                TextButton(
                  onPressed: () => ref
                      .read(authControllerProvider.notifier)
                      .continueAsGuest(),
                  child: Text(authStrings.welcomeSkip),
                ),
                const SizedBox(height: AppSpacing.xs8),
                Text(
                  strings.welcomeHint,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(height: AppSpacing.xs8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelMd.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool busy;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.paperWhite,
        foregroundColor: AppColors.coffeeBean,
        side: BorderSide(color: AppColors.outline.withValues(alpha: 0.25)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md24,
          vertical: AppSpacing.sm16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/google_g.png',
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.g_mobiledata,
                    size: 20,
                    color: AppColors.coffeeBean,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs8),
                Flexible(
                  child: Text(
                    label,
                    style: AppTextStyles.bodyLg.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.coffeeBean,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
