// Campaign card (#015): Arabic kind label, optimistic active Switch with
// rollback on failure, edit pencil (date pickers) and the double-points note.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_repositories.dart';

String _formatDate(DateTime? date) {
  if (date == null) return '—';
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class CampaignCard extends StatelessWidget {
  const CampaignCard({
    super.key,
    required this.campaign,
    required this.strings,
    required this.onToggleActive,
    required this.onEdit,
  });

  final Campaign campaign;
  final AdminStrings strings;
  final Future<void> Function(bool active) onToggleActive;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs8,
          vertical: 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign.nameAr?.isNotEmpty == true
                            ? campaign.nameAr!
                            : strings.kindLabel(campaign.kind),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        strings.kindLabel(campaign.kind),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.secondary,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: strings.edit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
              ],
            ),
            Text(
              '${_formatDate(campaign.startsAt)} → ${_formatDate(campaign.endsAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.outline,
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: campaign.active,
              onChanged: (value) => onToggleActive(value),
              title: Text(
                campaign.active ? strings.available : strings.unavailable,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (campaign.kind == 'double_points' && campaign.active)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs8),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        strings.doublePointsNote,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.secondary),
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

/// Collected values from the edit/new dialog.
class CampaignDialogResult {
  const CampaignDialogResult({
    required this.kind,
    required this.nameAr,
    this.startsAt,
    this.endsAt,
  });

  final String kind;
  final String nameAr;
  final DateTime? startsAt;
  final DateTime? endsAt;
}

/// Edit/new dialog: kind dropdown + AR name + start/end date pickers.
Future<CampaignDialogResult?> showCampaignDialog({
  required BuildContext context,
  required AdminStrings strings,
  Campaign? initial,
}) {
  return showDialog<CampaignDialogResult>(
    context: context,
    builder: (dialogContext) => _CampaignDialog(
      strings: strings,
      initial: initial,
    ),
  );
}

class _CampaignDialog extends StatefulWidget {
  const _CampaignDialog({required this.strings, this.initial});

  final AdminStrings strings;
  final Campaign? initial;

  @override
  State<_CampaignDialog> createState() => _CampaignDialogState();
}

class _CampaignDialogState extends State<_CampaignDialog> {
  late String _kind = widget.initial?.kind ?? Campaign.kinds.first;
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initial?.nameAr ?? '');
  late DateTime? _startsAt = widget.initial?.startsAt;
  late DateTime? _endsAt = widget.initial?.endsAt;

  Future<void> _pick({required bool isStart}) async {
    final now = DateTime.now();
    final current = isStart ? _startsAt : _endsAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() => isStart ? _startsAt = picked : _endsAt = picked);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(
        widget.initial == null ? strings.newCampaign : strings.edit,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration:
                  InputDecoration(labelText: strings.campaignKindLabel),
              items: [
                for (final kind in Campaign.kinds)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(strings.kindLabel(kind)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _kind = value ?? _kind),
            ),
            TextField(
              controller: _nameController,
              decoration:
                  InputDecoration(labelText: strings.campaignNameLabel),
            ),
            const SizedBox(height: AppSpacing.xs8),
            Row(
              children: [
                Expanded(child: Text('${strings.startsAtLabel}: ${_formatDate(_startsAt)}')),
                TextButton(
                  onPressed: () => _pick(isStart: true),
                  child: Text(strings.pickDate),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text('${strings.endsAtLabel}: ${_formatDate(_endsAt)}')),
                TextButton(
                  onPressed: () => _pick(isStart: false),
                  child: Text(strings.pickDate),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            CampaignDialogResult(
              kind: _kind,
              nameAr: _nameController.text.trim(),
              startsAt: _startsAt,
              endsAt: _endsAt,
            ),
          ),
          child: Text(strings.save),
        ),
      ],
    );
  }
}
