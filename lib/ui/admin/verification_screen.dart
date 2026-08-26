// Admin/Staff verification screen — RISK-06 (issue #51).
// Deferred-loaded wrapper around VerificationQueuePanel so router stays
// consistent with AGENTS.md ADR-0011 `deferred as` pattern (staff_board,
// admin_dashboard, lookup, driver_home). Arabic-first RTL, Heritage Hearth.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_risk.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/verification_queue_panel.dart';

class VerificationScreen extends ConsumerWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = RiskStrings.of(lang);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(strings.title),
      ),
      body: const VerificationQueuePanel(),
    );
  }
}
