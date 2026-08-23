// Rules editor (#015): app_config rows grouped (نقاط/أختام/توصيل/تيرات/حدود),
// tap a row → edit dialog, حفظ = per-row upsert then loyalty config refresh.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_repositories.dart';

class RulesEditor extends StatelessWidget {
  const RulesEditor({
    super.key,
    required this.strings,
    required this.values,
    required this.onSave,
  });

  final AdminStrings strings;

  /// Current `{key: scalar}` snapshot of app_config.
  final Map<String, dynamic> values;
  final Future<void> Function(String key, Object value) onSave;

  String _groupLabel(String group) => switch (group) {
        'points' => strings.groupPoints,
        'stamps' => strings.groupStampsRedemption,
        'delivery' => strings.groupDelivery,
        'tiers' => strings.groupTiers,
        'limits' => strings.groupProtectionLimits,
        _ => group,
      };

  Future<void> _editRow(BuildContext context, String key) async {
    final controller = TextEditingController(
      text: values[key]?.toString() ?? '',
    );
    final isIntKey = RulesRepository.intKeys.contains(key);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.ruleLabels[key] ?? key),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              isIntKey ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.save),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final raw = controller.text.trim().replaceAll(',', '.');
    final Object value = isIntKey
        ? int.tryParse(raw) ?? num.tryParse(raw)?.toInt() ?? 0
        : num.tryParse(raw) ?? 0.0;
    await onSave(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in RulesRepository.groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs8,
              bottom: 4,
            ),
            child: Text(
              _groupLabel(entry.key),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.secondary,
                  ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final key in entry.value)
                  ListTile(
                    dense: true,
                    title: Text(strings.ruleLabels[key] ?? key),
                    trailing: Text(
                      values[key]?.toString() ?? '—',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                          ),
                    ),
                    onTap: () => _editRow(context, key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs8),
        ],
      ],
    );
  }
}
