import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/session_controller.dart';

Future<void> showRoleSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const RoleSwitcherSheet(),
  );
}

class RoleSwitcherSheet extends ConsumerWidget {
  const RoleSwitcherSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final strings = AppStrings.of(session.lang);
    final roles = [
      (AppRole.customer, strings.roleCustomer, Icons.person_outline),
      (AppRole.staff, strings.roleStaff, Icons.support_agent_outlined),
      (AppRole.driver, strings.roleDriver, Icons.pedal_bike_outlined),
      (AppRole.admin, strings.roleAdmin, Icons.manage_accounts_outlined),
    ];

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
          const SizedBox(height: AppSpacing.xs8),
          for (final (role, label, icon) in roles)
            ListTile(
              leading: Icon(icon, color: AppColors.primary),
              title: Text(label, style: AppTextStyles.bodyLg),
              trailing: session.role == role
                  ? const Icon(Icons.check_circle, color: AppColors.secondary)
                  : null,
              onTap: () =>
                  ref.read(sessionControllerProvider.notifier).setRole(role),
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
