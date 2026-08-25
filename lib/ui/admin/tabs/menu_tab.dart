// Menu tab (ARCH-02 split): extracted from admin_dashboard_screen.dart.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_db.dart';
import '../../../data/repos/admin_menu_repository.dart';
import '../widgets/menu_editor_sheet.dart';

void _showErrorToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class MenuTab extends ConsumerStatefulWidget {
  const MenuTab({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<MenuTab> createState() => MenuTabState();
}

class MenuTabState extends ConsumerState<MenuTab> {
  List<AdminCategory>? _categories;
  List<AdminMenuItem>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final catalog =
          await ref.read(adminMenuRepositoryProvider).listCatalog();
      if (!mounted) return;
      setState(() {
        _categories = catalog.categories;
        _items = catalog.items;
        _loading = false;
      });
    } on AdminAccessDeniedException {
      widget.onAccessDenied();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setAvailability(AdminMenuItem item, bool available) async {
    final index = _items!.indexOf(item);
    setState(() {
      _items![index] = _withAvailability(item, available);
    });
    try {
      await ref
          .read(adminMenuRepositoryProvider)
          .setAvailability(item.id, available);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items![index] = item);
      _showErrorToast(context, widget.strings.revertedError);
    }
  }

  AdminMenuItem _withAvailability(AdminMenuItem item, bool available) =>
      AdminMenuItem(
        id: item.id,
        slug: item.slug,
        nameAr: item.nameAr,
        nameEn: item.nameEn,
        descAr: item.descAr,
        descEn: item.descEn,
        priceEgp: item.priceEgp,
        isAvailable: available,
        sort: item.sort,
        categoryId: item.categoryId,
        categorySlug: item.categorySlug,
        categoryNameAr: item.categoryNameAr,
        imageUrl: item.imageUrl,
      );

  Future<void> _confirmDelete(AdminMenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.deleteItemTitle),
        content: Text(
          widget.strings.deleteItemBodyFn(item.nameAr),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(widget.strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final payload = item.toPayload();
    final index = _items!.indexOf(item);
    setState(() => _items!.removeAt(index));
    try {
      await ref.read(adminMenuRepositoryProvider).deleteItem(item.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items!.insert(index, item));
      _showErrorToast(context, widget.strings.revertedError);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.strings.deleteItemTitle),
          action: SnackBarAction(
            label: widget.strings.undo,
            onPressed: () async {
              try {
                await ref
                    .read(adminMenuRepositoryProvider)
                    .reinsertRow(payload);
              } catch (_) {}
              await _load();
            },
          ),
        ),
      );
  }

  Future<void> _openEditor({AdminMenuItem? initial}) async {
    final categories = _categories ?? const <AdminCategory>[];
    final draft = await showMenuEditorSheet(
      context,
      strings: widget.strings,
      categories: categories,
      initial: initial,
    );
    if (draft == null || !mounted) return;
    try {
      await ref
          .read(adminMenuRepositoryProvider)
          .upsertItem(draft, id: initial?.id);
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _items ?? const <AdminMenuItem>[];
    if (items.isEmpty) {
      return Center(child: Text(widget.strings.noData));
    }
    // Group by category preserving catalog order.
    final groups = <String?, List<AdminMenuItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.categorySlug, () => []).add(item);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(widget.strings.addItem),
              onPressed: () => _openEditor(),
            ),
          ),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs8, bottom: 4),
              child: Text(
                entry.value.first.categoryNameAr ?? entry.key ?? '',
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
                  for (final item in entry.value)
                    ListTile(
                      dense: true,
                      leading: item.imageUrl == null || item.imageUrl!.isEmpty
                          ? const Icon(Icons.image_outlined, size: 20, color: AppColors.outline)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                imageUrl: item.imageUrl!,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                                ),
                                errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 20, color: AppColors.outline),
                                memCacheWidth: 72,
                                memCacheHeight: 72,
                              ),
                            ),
                      title: Text(
                        item.nameAr,
                        style: TextStyle(
                          color:
                              item.isAvailable ? null : AppColors.textMuted,
                          decoration: item.isAvailable
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(
                        '${item.priceEgp} ${widget.strings.currencySuffix}',
                      ),
                      onLongPress: () => _confirmDelete(item),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: item.isAvailable,
                            onChanged: (value) =>
                                _setAvailability(item, value),
                          ),
                          IconButton(
                            tooltip: widget.strings.edit,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _openEditor(initial: item),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs8),
          ],
        ],
      ),
    );
  }
}
