// Dine-in walk-in Check-in sheet (#012, FEATURES §6.2 / §11.31 manual
// fallback): manual phone entry (+20 regex validated inline), spend amount,
// داخل/تراس area chips and an optional table number. Submission delegates to
// the [onSubmit] callback (the board wires it to StaffOrdersRepo.registerVisit)
// and surfaces Arabic errors inline; success pops so the caller snackbars.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_staff.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/staff_orders_repository.dart';

/// Canonical Customer phone shape — same pattern as the auth validator.
final RegExp kEgyptianPhonePattern = RegExp(r'^\+20[0-9]{10}$');

/// Composes the `table_area` tag from the chosen area + optional table no.
String composeTableArea({
  required String? area,
  required String? tableNumber,
  String Function(String table)? tableLabel,
}) {
  final parts = [
    if (area != null && area.trim().isNotEmpty) area.trim(),
    if (tableNumber != null && tableNumber.trim().isNotEmpty)
      tableLabel?.call(tableNumber.trim()) ?? 'طاولة ${tableNumber.trim()}',
  ];
  return parts.join(' - ');
}

class CheckInSheet extends StatefulWidget {
  const CheckInSheet({
    super.key,
    required this.strings,
    required this.onSubmit,
  });

  final StaffStrings strings;

  /// Returns the recorded outcome; throw to surface an error inline.
  final Future<VisitRecorded> Function(CheckInInput input) onSubmit;

  @override
  State<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<CheckInSheet> {
  final _phoneController = TextEditingController();
  final _spendController = TextEditingController();
  final _tableController = TextEditingController();
  String? _area;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _spendController.dispose();
    _tableController.dispose();
    super.dispose();
  }

  bool get _formValid =>
      kEgyptianPhonePattern.hasMatch(_phoneController.text.trim()) &&
      int.tryParse(_spendController.text.trim()) != null &&
      int.parse(_spendController.text.trim()) >= 0;

  Future<void> _submit() async {
    final strings = widget.strings;
    final phone = _phoneController.text.trim();
    if (!kEgyptianPhonePattern.hasMatch(phone)) {
      setState(() => _error = strings.errorPhone);
      return;
    }
    final spend = int.tryParse(_spendController.text.trim());
    if (spend == null || spend < 0) {
      setState(() => _error = strings.errorSpend);
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    VisitRecorded? recorded;
    try {
      recorded = await widget.onSubmit(
        CheckInInput(
          phone: phone,
          spendEgp: spend,
          tableArea: composeTableArea(
            area: _area,
            tableNumber: _tableController.text,
            tableLabel: widget.strings.table,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(recorded);
    } on StaffPermissionException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '${strings.lockTitle}\n${strings.lockHint}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = strings.errorGeneric;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.sm16,
        right: AppSpacing.sm16,
        top: AppSpacing.sm16,
        bottom: bottomInset + AppSpacing.sm16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.checkInTitle, style: AppTextStyles.titleMd),
            const SizedBox(height: AppSpacing.xs8),
            TextField(
              controller: _phoneController,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: strings.fieldPhone,
                hintText: strings.phoneHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xs8),
            TextField(
              controller: _spendController,
              keyboardType: const TextInputType.numberWithOptions(),
              decoration: InputDecoration(
                labelText: strings.fieldSpend,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xs8),
            Text(strings.fieldArea, style: AppTextStyles.bodySm),
            const SizedBox(height: 4),
            Wrap(
              spacing: AppSpacing.xs8,
              children: [
                for (final option in [strings.areaInside, strings.areaTerrace])
                  ChoiceChip(
                    label: Text(option),
                    selected: _area == option,
                    onSelected: (selected) =>
                        setState(() => _area = selected ? option : null),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs8),
            TextField(
              controller: _tableController,
              keyboardType: const TextInputType.numberWithOptions(),
              decoration: InputDecoration(
                labelText: strings.fieldTable,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs8),
              Text(
                _error!,
                style:
                    AppTextStyles.bodySm.copyWith(color: AppColors.error),
              ),
            ],
            const SizedBox(height: AppSpacing.sm16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_submitting || !_formValid) ? null : _submit,
                child: Text(
                  _submitting ? strings.checkInSaving : strings.checkInSubmit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience entry used by the board app bar; completes with the recorded
/// outcome (null when dismissed or failed inline).
Future<VisitRecorded?> showCheckInSheet(
  BuildContext context, {
  required StaffStrings strings,
  required Future<VisitRecorded> Function(CheckInInput input) onSubmit,
}) {
  return showModalBottomSheet<VisitRecorded>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CheckInSheet(strings: strings, onSubmit: onSubmit),
  );
}
