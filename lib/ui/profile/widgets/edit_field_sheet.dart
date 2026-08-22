// Edit field bottom sheet (#011): one text value (+ optional address label
// selector) with validation. حفظ runs the caller's save — failure keeps the
// sheet open with an inline error, success pops it and the caller snackbars.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Strict `YYYY-MM-DD` parser for the birthdate editor (unit-tested):
/// rejects overflow dates like 2001-02-30 and future dates.
DateTime? parseBirthdateInput(String raw) {
  final value = raw.trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  if (parsed.isAfter(DateTime.now())) return null;
  return parsed;
}

/// What a saved edit produced: the trimmed text plus the selected label
/// index (only meaningful when [showEditFieldSheet] got label choices).
class EditFieldValue {
  const EditFieldValue(this.text, {this.labelIndex = 0});

  final String text;
  final int labelIndex;
}

Future<void> showEditFieldSheet(
  BuildContext context, {
  required String title,
  required String initialValue,
  required String saveLabel,
  required String cancelLabel,
  required String saveFailedError,
  String? hint,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  int maxLines = 1,
  List<String> labelChoices = const [],
  int initialLabelIndex = 0,
  String? Function(String raw)? validate,
  Key? textFieldKey,
  required Future<void> Function(EditFieldValue value) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.paperWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl24)),
    ),
    builder: (_) => _EditFieldSheet(
      title: title,
      initialValue: initialValue,
      saveLabel: saveLabel,
      cancelLabel: cancelLabel,
      saveFailedError: saveFailedError,
      hint: hint,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      labelChoices: labelChoices,
      initialLabelIndex: initialLabelIndex,
      validate: validate,
      textFieldKey: textFieldKey,
      onSave: onSave,
    ),
  );
}

class _EditFieldSheet extends StatefulWidget {
  const _EditFieldSheet({
    required this.title,
    required this.initialValue,
    required this.saveLabel,
    required this.cancelLabel,
    required this.saveFailedError,
    required this.onSave,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.labelChoices = const [],
    this.initialLabelIndex = 0,
    this.validate,
    this.textFieldKey,
  });

  final String title;
  final String initialValue;
  final String saveLabel;
  final String cancelLabel;
  final String saveFailedError;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final List<String> labelChoices;
  final int initialLabelIndex;
  final String? Function(String raw)? validate;
  final Key? textFieldKey;
  final Future<void> Function(EditFieldValue value) onSave;

  @override
  State<_EditFieldSheet> createState() => _EditFieldSheetState();
}

class _EditFieldSheetState extends State<_EditFieldSheet> {
  late final TextEditingController _controller;
  late int _labelIndex;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _labelIndex = widget.initialLabelIndex;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final problem = widget.validate?.call(_controller.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        EditFieldValue(
          _controller.text.trim(),
          labelIndex: _labelIndex,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.saveFailedError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md24,
          AppSpacing.sm16,
          AppSpacing.md24,
          AppSpacing.md24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: AppTextStyles.titleMd),
            const SizedBox(height: AppSpacing.sm16),
            if (widget.labelChoices.isNotEmpty) ...[
              Wrap(
                spacing: AppSpacing.xs8,
                children: [
                  for (var i = 0; i < widget.labelChoices.length; i++)
                    ChoiceChip(
                      label: Text(widget.labelChoices[i]),
                      selected: _labelIndex == i,
                      onSelected: (_) => setState(() => _labelIndex = i),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm16),
            ],
            TextField(
              key: widget.textFieldKey,
              controller: _controller,
              keyboardType:
                  widget.keyboardType ?? TextInputType.multiline,
              inputFormatters: widget.inputFormatters,
              maxLines: widget.maxLines,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.hint,
                errorText: _error,
                errorMaxLines: 2,
              ),
              style: AppTextStyles.bodyLg,
            ),
            const SizedBox(height: AppSpacing.md24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(widget.cancelLabel),
                ),
                const SizedBox(width: AppSpacing.xs8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(widget.saveLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
