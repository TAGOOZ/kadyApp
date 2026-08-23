// Item detail bottom sheet (issue #002): configure size/sugar/addons/note,
// pick quantity, then add to cart. Rounded 24 top corners per design refs.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_menu.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/menu_models.dart';
import '../../domain/cart_controller.dart';

/// Branded photo placeholder — gradient + ☕ — shared by the menu cards and
/// this sheet until photos land via `cached_network_image` in a later slice
/// (`imageUrl` stays on the model).
class MenuPhotoPlaceholder extends StatelessWidget {
  const MenuPhotoPlaceholder({
    super.key,
    this.height = 96,
    this.width,
    this.iconSize = 32,
    this.radius = AppRadii.mdLg12,
  });

  final double height;
  final double? width;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.parchment, AppColors.primaryFixedTint],
        ),
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
      alignment: Alignment.center,
      child: Text('☕', style: TextStyle(fontSize: iconSize)),
    );
  }
}

Future<void> showItemDetailSheet(BuildContext context, MenuItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.paperWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl24)),
    ),
    builder: (_) => _ItemDetailSheet(item: item),
  );
}

class _ItemDetailSheet extends ConsumerStatefulWidget {
  const _ItemDetailSheet({required this.item});

  final MenuItem item;

  @override
  ConsumerState<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends ConsumerState<_ItemDetailSheet> {
  int _sizeIndex = 0;
  int _sugarIndex = 0;
  final Set<String> _addons = {};
  final TextEditingController _noteController = TextEditingController();
  int _qty = 1;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  int get _unitPriceEgp {
    final addonTotal = _addons.fold<int>(
      0,
      (sum, id) => sum + (ItemConfig.addonPricesEgp[id] ?? 0),
    );
    return widget.item.priceEgp +
        ItemConfig.sizeDeltasEgp[_sizeIndex] +
        addonTotal;
  }

  ItemConfig buildConfig() {
    final note = _noteController.text.trim();
    return ItemConfig(
      sizeIndex: _sizeIndex,
      sugarIndex: _sugarIndex,
      addons: Set.of(_addons),
      note: note.isEmpty ? null : note,
    );
  }

  void _toggleAddon(String id) {
    setState(() {
      if (!_addons.remove(id)) {
        _addons.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = MenuStringsCatalog.of(lang);
    final isFavorite = ref.watch(favoritesProvider).contains(widget.item.id);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs8),
                width: 40,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.parchment,
                  borderRadius: BorderRadius.all(Radius.circular(AppRadii.pill)),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.margin20,
                  0,
                  AppSpacing.margin20,
                  AppSpacing.md24,
                ),
                children: [
                  _PhotoHeader(item: widget.item, isFavorite: isFavorite),
                  const SizedBox(height: AppSpacing.sm16),
                  Text(
                    widget.item.name(lang),
                    style: AppTextStyles.headlineMobile.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    widget.item.nameEn,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs8),
                  if (widget.item.desc(lang).isNotEmpty) ...[
                    Text(
                      widget.item.desc(lang),
                      style: AppTextStyles.bodySm,
                    ),
                    const SizedBox(height: AppSpacing.xs8),
                  ],
                  Text(
                    strings.price(_unitPriceEgp),
                    style: AppTextStyles.priceLg.copyWith(
                       color: AppColors.secondary,
                     ),
                  ),
                  const SizedBox(height: AppSpacing.sm16),
                  _SectionTitle(strings.sizeLabel),
                  const SizedBox(height: AppSpacing.xs8),
                  Wrap(
                    spacing: AppSpacing.xs8,
                    runSpacing: AppSpacing.xs8,
                    children: [
                      for (var i = 0; i < strings.sizeNames.length; i++)
                        _OptionChip(
                          label: _sizeLabel(strings, i),
                          active: _sizeIndex == i,
                          onTap: () => setState(() => _sizeIndex = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm16),
                  _SectionTitle(strings.sugarLabel),
                  const SizedBox(height: AppSpacing.xs8),
                  Wrap(
                    spacing: AppSpacing.xs8,
                    runSpacing: AppSpacing.xs8,
                    children: [
                      for (var i = 0; i < strings.sugarNames.length; i++)
                        _OptionChip(
                          label: strings.sugarNames[i],
                          active: _sugarIndex == i,
                          onTap: () => setState(() => _sugarIndex = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm16),
                  _SectionTitle(strings.addonsLabel),
                  const SizedBox(height: AppSpacing.xs8),
                  ...ItemConfig.addonPricesEgp.keys.map(
                    (id) => _AddonRow(
                      label: strings.addonName(id),
                      delta: strings.addonDelta(
                        ItemConfig.addonPricesEgp[id] ?? 0,
                      ),
                      checked: _addons.contains(id),
                      onChanged: (_) => _toggleAddon(id),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm16),
                  _SectionTitle(strings.noteLabel),
                  const SizedBox(height: AppSpacing.xs8),
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: strings.noteHint,
                      filled: true,
                      fillColor: AppColors.parchment.withValues(alpha: 0.6),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadii.mdLg12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _StickyFooter(
              item: widget.item,
              strings: strings,
              unitPriceEgp: _unitPriceEgp,
              buildConfig: buildConfig,
              qty: _qty,
              onQtyChanged: (q) => setState(() => _qty = q),
            ),
          ],
        ),
      ),
    );
  }

  String _sizeLabel(MenuStrings strings, int index) {
    final delta = ItemConfig.sizeDeltasEgp[index];
    return delta == 0 ? strings.sizeNames[index] : '${strings.sizeNames[index]} · +$delta';
  }
}

class _PhotoHeader extends ConsumerWidget {
  const _PhotoHeader({required this.item, required this.isFavorite});

  final MenuItem item;
  final bool isFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        const MenuPhotoPlaceholder(
          height: 180,
          width: double.infinity,
          iconSize: 56,
          radius: AppRadii.lg16,
        ),
        PositionedDirectional(
          start: AppSpacing.xs8,
          top: AppSpacing.xs8,
          child: _CircleButton(
            icon: Icons.close,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        PositionedDirectional(
          end: AppSpacing.xs8,
          top: AppSpacing.xs8,
          child: _CircleButton(
            icon: isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? AppColors.secondary : null,
            onTap: () => ref.read(favoritesProvider.notifier).toggle(item.id),
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, this.color, required this.onTap});

  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paperWhite.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs8 - 4),
          child: Icon(icon, size: 20, color: color ?? AppColors.primary),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTextStyles.titleSm.copyWith(
         color: AppColors.primary,
       ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm16,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.parchment,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.25)),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySm.copyWith(
             fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.coffeeBean,
          ),
        ),
      ),
    );
  }
}

class _AddonRow extends StatelessWidget {
  const _AddonRow({
    required this.label,
    required this.delta,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final String delta;
  final bool checked;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.mdLg12),
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(value: checked, onChanged: onChanged),
            Expanded(child: Text(label, style: AppTextStyles.bodyLg)),
            Text(
              delta,
              style: AppTextStyles.priceSm.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickyFooter extends ConsumerWidget {
  const _StickyFooter({
    required this.item,
    required this.strings,
    required this.unitPriceEgp,
    required this.buildConfig,
    required this.qty,
    required this.onQtyChanged,
  });

  final MenuItem item;
  final MenuStrings strings;
  final int unitPriceEgp;
  final ItemConfig Function() buildConfig;
  final int qty;
  final ValueChanged<int> onQtyChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineTotal = unitPriceEgp * qty;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        border: Border(
          top: BorderSide(color: AppColors.outline.withValues(alpha: 0.25)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter16,
        AppSpacing.xs8,
        AppSpacing.gutter16,
        AppSpacing.sm16,
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.outline.withValues(alpha: 0.25)),
              borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: qty > 1 ? () => onQtyChanged(qty - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$qty', style: AppTextStyles.titleSm),
                IconButton(
                  onPressed: () => onQtyChanged(qty + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs8),
          Expanded(
            child: FilledButton(
              onPressed: () {
                ref
                    .read(cartProvider.notifier)
                    .addItem(item, buildConfig(), qty: qty);
                Navigator.of(context).pop();
              },
              child: Text(strings.addToCart(lineTotal)),
            ),
          ),
        ],
      ),
    );
  }
}
