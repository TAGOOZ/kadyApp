// Rules tab (ARCH-02 split): extracted from admin_dashboard_screen.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_db.dart';
import '../../../data/repos/admin_rules_repository.dart';
import '../../../domain/loyalty_controller.dart';
import '../widgets/rules_editor.dart';

void _showErrorToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class RulesTab extends ConsumerStatefulWidget {
  const RulesTab({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<RulesTab> createState() => RulesTabState();
}

class RulesTabState extends ConsumerState<RulesTab> {
  Map<String, dynamic>? _values;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final values = await ref.read(rulesRepositoryProvider).fetchAll();
      if (!mounted) return;
      setState(() {
        _values = values;
        _loading = false;
      });
    } on AdminAccessDeniedException {
      widget.onAccessDenied();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save(String key, Object value) async {
    try {
      await ref.read(rulesRepositoryProvider).save(key, value);
      if (!mounted) return;
      setState(() => _values?[key] = value);
      // Push fresh config into the live loyalty engine.
      try {
        await ref.read(loyaltyProvider.notifier).refreshConfig();
      } catch (_) {}
      if (!mounted) return;
      _showErrorToast(context, widget.strings.saved);
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final values = _values ?? const <String, dynamic>{};
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: RulesEditor(
          strings: widget.strings,
          values: values,
          onSave: _save,
        ),
      ),
    );
  }
}
