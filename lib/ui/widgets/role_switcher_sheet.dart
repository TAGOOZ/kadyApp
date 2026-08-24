import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/profile_repository.dart';
import '../../domain/auth_controller.dart';
import '../../domain/session_controller.dart';

bool get isRoleSwitcherEnabled {
  const enabledFlag = String.fromEnvironment('ENABLE_ROLE_SWITCHER') == 'true';
  return kDebugMode || enabledFlag;
}

Future<void> showRoleSwitcher(BuildContext context) {
  if (!isRoleSwitcherEnabled) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const RoleSwitcherSheet(),
  );
}

class RoleSwitcherSheet extends ConsumerStatefulWidget {
  const RoleSwitcherSheet({super.key});

  @override
  ConsumerState<RoleSwitcherSheet> createState() => _RoleSwitcherSheetState();
}

class _RoleSwitcherSheetState extends ConsumerState<RoleSwitcherSheet> {
  @override
  void initState() {
    super.initState();
    // Opportunistic server sync — fixes stale local fake without tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authControllerProvider);
      final userId = auth.googleUser?.id;
      if (userId != null && userId.isNotEmpty) {
        // ignore: discarded_futures
        ref.read(sessionControllerProvider.notifier).syncRoleFromServer(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final strings = AppStrings.of(session.lang);
    final auth = ref.watch(authControllerProvider);
    final roles = [
      (AppRole.customer, strings.roleCustomer, Icons.person_outline),
      (AppRole.staff, strings.roleStaff, Icons.support_agent_outlined),
      (AppRole.driver, strings.roleDriver, Icons.pedal_bike_outlined),
      (AppRole.admin, strings.roleAdmin, Icons.manage_accounts_outlined),
    ];

    Future<void> handleTap(AppRole requested) async {
      // No authenticated user -> only customer is allowed locally.
      final userId = auth.googleUser?.id;
      if (userId == null || userId.isEmpty) {
        if (requested != AppRole.customer) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                session.lang == AppLang.ar
                    ? 'سجّل دخول Google أولاً — الترقية تتم من الخادم فقط'
                    : 'Sign in with Google first — promotion is server-only',
              ),
            ),
          );
          return;
        }
        await ref.read(sessionControllerProvider.notifier).setRole(requested);
        if (context.mounted) Navigator.of(context).pop();
        return;
      }

      // Authenticated: authoritative check against profiles.role.
      try {
        final gateway = ref.read(profileRoleGatewayProvider);
        final raw = await gateway.fetchRole(userId);
        AppRole serverRole = AppRole.customer;
        if (raw != null) {
          for (final r in AppRole.values) {
            if (r.name == raw) {
              serverRole = r;
              break;
            }
          }
        }
        // Keep local cache coherent if it drifted (old fake value).
        if (serverRole != session.role) {
          await ref
              .read(sessionControllerProvider.notifier)
              .syncRoleFromServer(userId);
        }
        if (requested != serverRole) {
          if (!context.mounted) return;
          final serverLabel = switch (serverRole) {
            AppRole.customer => strings.roleCustomer,
            AppRole.staff => strings.roleStaff,
            AppRole.driver => strings.roleDriver,
            AppRole.admin => strings.roleAdmin,
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                session.lang == AppLang.ar
                    ? 'دورك الحالي: $serverLabel — الترقية تتم بتشغيل: update profiles set role=\'$requested\' where user_id=\'$userId\''
                    : 'Your role: $serverLabel — ask admin to run: update profiles set role=\'$requested\' where user_id=\'$userId\'',
              ),
            ),
          );
          return;
        }
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              session.lang == AppLang.ar
                  ? 'تعذّر التحقق من الدور — تحقق من الاتصال'
                  : 'Could not verify role — check connection',
            ),
          ),
        );
        return;
      }

      await ref.read(sessionControllerProvider.notifier).setRole(requested);
      if (context.mounted) Navigator.of(context).pop();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.margin20,
            ),
            child: Text(strings.roleSwitcherTitle,
                style: AppTextStyles.titleMd),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.margin20,
              vertical: 4,
            ),
            child: Text(
              session.lang == AppLang.ar
                  ? 'الدور مرتبط بالخادم (profiles.role) — التبديل المحلي وحده لا يمنح الصلاحيات'
                  : 'Role is server-managed (profiles.role) — local switch alone grants no access',
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: AppSpacing.xs8),
          for (final (role, label, icon) in roles)
            ListTile(
              leading: Icon(icon, color: AppColors.primary),
              title: Text(label, style: AppTextStyles.bodyLg),
              trailing: session.role == role
                  ? const Icon(Icons.check_circle, color: AppColors.secondary)
                  : null,
              onTap: () => handleTap(role),
            ),
          Divider(
            indent: AppSpacing.margin20,
            endIndent: AppSpacing.margin20,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.margin20,
            ),
            child: Text(strings.languageLabel, style: AppTextStyles.titleMd),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.margin20,
              vertical: AppSpacing.sm16,
            ),
            child: SegmentedButton<AppLang>(
              segments: [
                ButtonSegment(value: AppLang.ar, label: Text(strings.langAr)),
                ButtonSegment(value: AppLang.en, label: Text(strings.langEn)),
              ],
              selected: {session.lang},
              onSelectionChanged: (selection) => ref
                  .read(localeNotifierProvider.notifier)
                  .setLang(selection.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.margin20,
              0,
              AppSpacing.margin20,
              AppSpacing.md24,
            ),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.close),
            ),
          ),
        ],
      ),
    );
  }
}
