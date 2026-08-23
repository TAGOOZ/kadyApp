// Menu editor bottom sheet (#015): full AR/EN fields, price int, category
// dropdown, sort int — save = upsert payload (insert for new items).
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_repositories.dart';

/// Shows the editor sheet; returns the collected [MenuItemDraft] on save,
/// null on dismiss. For new items ([initial] absent) the slug is generated.
Future<MenuItemDraft?> showMenuEditorSheet(
  BuildContext context, {
  required AdminStrings strings,
  required List<AdminCategory> categories,
  AdminMenuItem? initial,
}) {
  return showModalBottomSheet<MenuItemDraft>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MenuEditorSheet(
      strings: strings,
      categories: categories,
      initial: initial,
    ),
  );
}

class _MenuEditorSheet extends StatefulWidget {
  const _MenuEditorSheet({
    required this.strings,
    required this.categories,
    this.initial,
  });

  final AdminStrings strings;
  final List<AdminCategory> categories;
  final AdminMenuItem? initial;

  @override
  State<_MenuEditorSheet> createState() => _MenuEditorSheetState();
}

class _MenuEditorSheetState extends State<_MenuEditorSheet> {
  late int? _categoryId =
      widget.initial?.categoryId ?? widget.categories.firstOrNull?.id;
  late final TextEditingController _nameAr =
      TextEditingController(text: widget.initial?.nameAr ?? '');
  late final TextEditingController _nameEn =
      TextEditingController(text: widget.initial?.nameEn ?? '');
  late final TextEditingController _descAr =
      TextEditingController(text: widget.initial?.descAr ?? '');
  late final TextEditingController _descEn =
      TextEditingController(text: widget.initial?.descEn ?? '');
  late final TextEditingController _price = TextEditingController(
    text: (widget.initial?.priceEgp ?? 0).toString(),
  );
  late final TextEditingController _sort = TextEditingController(
    text: (widget.initial?.sort ?? 0).toString(),
  );

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _descAr.dispose();
    _descEn.dispose();
    _price.dispose();
    _sort.dispose();
    super.dispose();
  }

  void _submit() {
    final category = widget.categories.where((c) => c.id == _categoryId).firstOrNull;
    if (category == null) return Navigator.of(context).pop();
    Navigator.of(context).pop(
      MenuItemDraft(
        slug: widget.initial != null
            ? widget.initial!.slug
            : AdminMenuRepository.generateSlug(_nameEn.text),
        nameAr: _nameAr.text.trim(),
        nameEn: _nameEn.text.trim(),
        descAr: _descAr.text.trim(),
        descEn: _descEn.text.trim(),
        priceEgp: int.tryParse(_price.text.trim()) ?? 0,
        categoryId: category.id,
        sort: int.tryParse(_sort.text.trim()) ?? 0,
      ),
    );
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: InputDecoration(labelText: strings.fieldCategory),
              items: [
                for (final category in widget.categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.nameAr),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            TextField(
              controller: _nameAr,
              decoration: InputDecoration(labelText: strings.fieldNameAr),
            ),
            TextField(
              controller: _nameEn,
              decoration: InputDecoration(labelText: strings.fieldNameEn),
            ),
            TextField(
              controller: _descAr,
              decoration: InputDecoration(labelText: strings.fieldDescAr),
            ),
            TextField(
              controller: _descEn,
              decoration: InputDecoration(labelText: strings.fieldDescEn),
            ),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: strings.fieldPrice),
            ),
            TextField(
              controller: _sort,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: strings.fieldSort),
            ),
            const SizedBox(height: AppSpacing.xs8),
            FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(strings.save),
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
