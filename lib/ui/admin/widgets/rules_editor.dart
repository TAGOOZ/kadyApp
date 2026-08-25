// Rules editor (#015): app_config rows grouped (نقاط/أختام/توصيل/تيرات/حدود),
// tap a row → edit dialog, حفظ = per-row upsert then loyalty config refresh.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_rules_repository.dart';

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
        'extras' => strings.groupExtras,
        _ => group,
      };

  Future<void> _editRow(BuildContext context, String key) async {
    // Bool keys show a Switch dialog.
    if (RulesRepository.boolKeys.contains(key)) {
      final current = values[key];
      bool currentBool = false;
      if (current is bool) currentBool = current;
      if (current is num) currentBool = current != 0;
      if (current is String) currentBool = current.toLowerCase() == 'true';
      bool tapped = currentBool;
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(strings.ruleLabels[key] ?? key),
            content: SwitchListTile(
              title: Text(tapped ? strings.available : strings.unavailable),
              value: tapped,
              onChanged: (v) => setState(() => tapped = v),
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
        ),
      );
      if (saved != true) return;
      await onSave(key, tapped);
      return;
    }

    final controller = TextEditingController(
      text: values[key]?.toString() ?? '',
    );
    final isIntKey = RulesRepository.intKeys.contains(key);
    String? errorText;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(strings.ruleLabels[key] ?? key),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                isIntKey ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(errorText: errorText),
            onChanged: (_) {
              if (errorText != null) setState(() => errorText = null);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () {
                final raw = controller.text.trim().replaceAll(',', '.');
                if (raw.isEmpty) {
                  setState(() => errorText = strings.validationError);
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(strings.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final raw = controller.text.trim().replaceAll(',', '.');
    final Object value = isIntKey
        ? int.tryParse(raw) ?? num.tryParse(raw)?.toInt() ?? 0
        : num.tryParse(raw) ?? 0.0;
    // Cross-field validation: tiers ordering, positive checks.
    final validation = _validateKey(key, value, values);
    if (validation != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(validation)),
        );
      }
      return;
    }
    await onSave(key, value);
  }

  String? _validateKey(String key, Object value, Map<String, dynamic> all) {
    if (value is num) {
      if (value is int && value < 0 && key != 'dine_in_multiplier') return strings.validationError;
      if (key == 'points_per_10egp' && value is int && value <= 0) return strings.validationError;
      if (key == 'dine_in_multiplier' && value is double && value < 1.0) return strings.validationError;
      if (key == 'dine_in_multiplier' && value is int && value < 1) return strings.validationError;
      if (key == 'stamp_min_spend' && value is int && value <= 0) return strings.validationError;
      if (key == 'delivery_fee' && value < 0) return strings.validationError;
      if (key == 'rate_limit_max' && value is int && value <= 0) return strings.validationError;
      if (key == 'rate_limit_window_min' && value is int && value <= 0) return strings.validationError;
      if (key == 'group_checkin_count' && value is int && value < 2) return strings.validationError;
      if (key == 'group_bonus_points' && value is int && value < 0) return strings.validationError;
    }
    if (key == 'tier_silver' || key == 'tier_gold') {
      final silver = key == 'tier_silver' ? (value as num).toInt() : (all['tier_silver'] as num?)?.toInt() ?? 2000;
      final gold = key == 'tier_gold' ? (value as num).toInt() : (all['tier_gold'] as num?)?.toInt() ?? 5000;
      if (gold <= silver) return strings.validationError;
    }
    return null;
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
