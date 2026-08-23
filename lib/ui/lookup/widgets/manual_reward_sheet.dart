// Manual reward bottom sheet (#013, FEATURES §6.4 service recovery): reward
// type radio (+25 نقطة / مشروب مجاني / توبينج مجاني), reason dropdown
// (اعتذار عن تأخير / ضيف جديد / أخرى) and an optional note. Confirm pops with
// a [ManualRewardInput]; the screen performs the grant, snackbars and refreshes.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_lookup.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/customer_lookup_repository.dart';

class ManualRewardSheet extends StatefulWidget {
  const ManualRewardSheet({super.key, required this.strings});

  final LookupStrings strings;

  /// Convenience entry; completes with the chosen input (null when dismissed).
  static Future<ManualRewardInput?> show(
    BuildContext context,
    LookupStrings strings,
  ) {
    return showModalBottomSheet<ManualRewardInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManualRewardSheet(strings: strings),
    );
  }

  @override
  State<ManualRewardSheet> createState() => _ManualRewardSheetState();
}

class _ManualRewardSheetState extends State<ManualRewardSheet> {
  ManualRewardType _type = ManualRewardType.points25;
  ManualReason _reason = ManualReason.lateApology;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _typeLabel(ManualRewardType type) => switch (type) {
        ManualRewardType.points25 => widget.strings.rewardPoints25,
        ManualRewardType.freeDrink => widget.strings.rewardFreeDrink,
        ManualRewardType.freeTopping => widget.strings.rewardFreeTopping,
      };

  String _reasonLabel(ManualReason reason) => switch (reason) {
        ManualReason.lateApology => widget.strings.reasonLateApology,
        ManualReason.newGuest => widget.strings.reasonNewGuest,
        ManualReason.other => widget.strings.reasonOther,
      };

  void _confirm() {
    Navigator.of(context).pop(ManualRewardInput(
      type: _type,
      reason: _reason,
      note: _noteController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.sm16,
        right: AppSpacing.sm16,
        top: AppSpacing.sm16,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.rewardSheetTitle, style: AppTextStyles.titleMd),
            const SizedBox(height: AppSpacing.xs8),
            RadioGroup<ManualRewardType>(
              groupValue: _type,
              onChanged: (value) => setState(() => _type = value ?? _type),
              child: Column(
                children: [
                  for (final type in ManualRewardType.values)
                    RadioListTile<ManualRewardType>(
                      title: Text(_typeLabel(type)),
                      value: type,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs8),
            DropdownButtonFormField<ManualReason>(
              initialValue: _reason,
              decoration: InputDecoration(
                labelText: strings.reasonLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final reason in ManualReason.values)
                  DropdownMenuItem(
                    value: reason,
                    child: Text(_reasonLabel(reason)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _reason = value ?? _reason),
            ),
            const SizedBox(height: AppSpacing.xs8),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: strings.noteLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.cancel),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(
                  child: FilledButton(
                    onPressed: _confirm,
                    child: Text(strings.confirmAddCta),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
