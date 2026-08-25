// Menu editor bottom sheet (#015): full AR/EN fields, price int, category
// dropdown, sort int — save = upsert payload (insert for new items).
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_menu_repository.dart';

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
  final _formKey = GlobalKey<FormState>();
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
  late final TextEditingController _imageUrl = TextEditingController(
    text: widget.initial?.imageUrl ?? '',
  );

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    _descAr.dispose();
    _descEn.dispose();
    _price.dispose();
    _sort.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  bool _isValidUrl(String value) {
    if (value.isEmpty) return true;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final category = widget.categories.where((c) => c.id == _categoryId).firstOrNull;
    if (category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.noData)),
      );
      return;
    }
    final imageRaw = _imageUrl.text.trim();
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
        imageUrl: imageRaw.isEmpty ? null : imageRaw,
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
      child: Form(
        key: _formKey,
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
                validator: (v) => v == null ? strings.fieldCategory : null,
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              TextFormField(
                controller: _nameAr,
                decoration: InputDecoration(labelText: strings.fieldNameAr),
                validator: (v) => (v == null || v.trim().isEmpty) ? strings.nameRequiredError : null,
              ),
              TextFormField(
                controller: _nameEn,
                decoration: InputDecoration(labelText: strings.fieldNameEn),
                validator: (v) => (v == null || v.trim().isEmpty) ? strings.nameRequiredError : null,
              ),
              TextFormField(
                controller: _descAr,
                decoration: InputDecoration(labelText: strings.fieldDescAr),
              ),
              TextFormField(
                controller: _descEn,
                decoration: InputDecoration(labelText: strings.fieldDescEn),
              ),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: strings.fieldPrice),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null) return strings.priceInvalidError;
                  if (n <= 0) return strings.pricePositiveError;
                  return null;
                },
              ),
              TextFormField(
                controller: _sort,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: strings.fieldSort),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null) return strings.sortInvalidError;
                  if (n < 0) return strings.sortPositiveError;
                  return null;
                },
              ),
              TextFormField(
                controller: _imageUrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: strings.fieldImageUrl,
                  hintText: 'https://...',
                ),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (!_isValidUrl(raw)) return strings.imageUrlInvalidError;
                  return null;
                },
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
      ),
    );
  }
}
