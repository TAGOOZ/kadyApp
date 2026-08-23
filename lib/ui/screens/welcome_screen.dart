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
      backgroundColor: AppColors.parchment,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.margin20,
                  AppSpacing.md24,
                  AppSpacing.margin20,
                  AppSpacing.sm16,
                ),
                child: Column(
                  children: [
                    // Hero — Stitch-inspired rounded coffee image with soft shadow
                    GestureDetector(
                      onLongPress: () => showRoleSwitcher(context),
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.xl24),
                          boxShadow: AppShadows.coffeeShadows(
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              'assets/images/menu_hero.png',
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
                                  child: Text('☕', style: TextStyle(fontSize: 64)),
                                ),
                              ),
                            ),
                            // Subtle parchment vignette
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    AppColors.coffeeBean.withValues(alpha: 0.08),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md24),
                    GestureDetector(
                      onLongPress: () => showRoleSwitcher(context),
                      child: const AppLogo(size: 72),
                    ),
                    const SizedBox(height: AppSpacing.sm16),
                    GestureDetector(
                      onLongPress: () => showRoleSwitcher(context),
                      child: Text(
                        strings.appName,
                        style: AppTextStyles.headlineLg.copyWith(
                          color: AppColors.coffeeBean,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs8),
                    Text(
                      'أهلاً وسهلاً بك في تطبيقنا!',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMd.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs8),
                    Text(
                      strings.tagline,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.textMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom card — Stitch rounded-top sheet
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.paperWhite,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadii.xl24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x144B2C20),
                    offset: Offset(0, -4),
                    blurRadius: 16,
                  ),
                ],
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
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.parchment,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md24),
                  // Google — primary, branded with G logo
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
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        backgroundColor: Colors.white,
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
                // Google G — inline SVG-free colored text
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    'G',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4285F4),
                    ),
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
