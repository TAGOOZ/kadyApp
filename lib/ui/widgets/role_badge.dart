// Reusable role badge — clean switch for any privileged shell (admin/staff/driver).
// Tap = debug → full sheet; release → quick "View as customer" toggle.
// Server role (profiles.role) stays authoritative; local role (SharedPreferences) is UX shell only (router.dart:133 _homeFor).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/auth_controller.dart';
import '../../domain/session_controller.dart';
import 'role_switcher_sheet.dart';

class RoleBadge extends ConsumerWidget {
  const RoleBadge({
    super.key,
    required this.icon,
    this.radius = 16,
    this.backgroundColor = AppColors.primaryContainer,
    this.foregroundColor = Colors.white,
  });

  final IconData icon;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final lang = ref.read(localeNotifierProvider);
    final session = ref.read(sessionControllerProvider);
    if (isRoleSwitcherEnabled) {
      await showRoleSwitcher(context);
      return;
    }
    // Release: quick toggle between server role and customer view.
    // Same google_user_id can order as customer (phone-keyed) while server stays admin/staff/driver.
    if (session.role != AppRole.customer) {
      await ref.read(sessionControllerProvider.notifier).setRole(AppRole.customer);
      if (context.mounted) context.go('/home');
      return;
    }
    final auth = ref.read(authControllerProvider);
    final userId = auth.googleUser?.id;
    if (userId == null || userId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang == AppLang.ar
                ? 'سجّل دخول Google أولاً — الترقية تتم من الخادم فقط'
                : 'Sign in with Google first — promotion is server-only'),
          ),
        );
      }
      return;
    }
    await ref.read(sessionControllerProvider.notifier).syncRoleFromServer(userId);
    if (!context.mounted) return;
    final synced = ref.read(sessionControllerProvider).role;
    if (synced != AppRole.customer) {
      context.go(switch (synced) {
        AppRole.staff => '/staff',
        AppRole.driver => '/driver',
        AppRole.admin => '/admin',
        AppRole.customer => '/home',
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang == AppLang.ar
              ? 'دورك الحالي: عميل — اطلب من المالك ترقية الحساب'
              : 'Your role: customer — ask admin to elevate your account'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    return Tooltip(
      message: lang == AppLang.ar ? 'تبديل الدور' : 'Switch role',
      child: InkWell(
        onTap: () => _onTap(context, ref),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          child: Icon(icon, size: radius == 16 ? 20 : 22, color: foregroundColor),
        ),
      ),
    );
  }
}
