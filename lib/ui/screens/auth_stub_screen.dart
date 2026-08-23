import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/session_controller.dart';

// TODO(slice-004): replace this stub with the real Google OAuth gate.
class AuthStubScreen extends ConsumerWidget {
  const AuthStubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final strings = AppStrings.of(session.lang);

    return Scaffold(
      appBar: AppBar(title: Text(strings.appName)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(strings.comingSoon, style: AppTextStyles.bodyLg),
            const SizedBox(height: AppSpacing.md24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(strings.close),
            ),
          ],
        ),
      ),
    );
  }
}
