import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/session_controller.dart';
import '../widgets/app_logo.dart';
import '../widgets/role_switcher_sheet.dart';

class PlaceholderPage extends ConsumerWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.line,
    this.showRoleTile = false,
  });

  final String title;
  final String line;
  final bool showRoleTile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final strings = AppStrings.of(session.lang);
    final roleLabel = roleNameOf(session.role, strings);

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
                  onLongPress: () {
                    if (!kDebugMode &&
                        const String.fromEnvironment('ENABLE_ROLE_SWITCHER') !=
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
                        const String.fromEnvironment('ENABLE_ROLE_SWITCHER') !=
                            'true') {
                      return;
                    }
                    showRoleSwitcher(context);
                  },
                  child: Text(title, style: AppTextStyles.headlineMobile),
                ),
                const SizedBox(height: AppSpacing.xs8),
                Chip(label: Text(roleLabel)),
                const SizedBox(height: AppSpacing.xs8),
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLg,
                ),
                if (showRoleTile) ...[
                  const SizedBox(height: AppSpacing.md24),
                  Card(
                    child: ListTile(
                      leading:
                          const Icon(Icons.swap_horiz, color: AppColors.primary),
                      title: Text(strings.roleSwitcherTile),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        if (!kDebugMode &&
                            const String.fromEnvironment(
                                    'ENABLE_ROLE_SWITCHER') !=
                                'true') {
                          return;
                        }
                        showRoleSwitcher(context);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
