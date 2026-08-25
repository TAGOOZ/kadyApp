// Featured carousel (#005 v3): replaces category shortcuts on the home hub.
// Single-brand cafés don't re-browse categories on home — home surfaces
// curated discovery (most-ordered / featured), Menu owns full browsing.
// Data: first 6 available items from the first page (no migration); v2 will
// use menu_items.is_featured when the migration lands (see note below).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_home.dart';
import '../../../core/l10n/strings_menu.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/menu_models.dart';
import '../../menu/menu_pagination_controller.dart';
import '../../menu/item_detail_sheet.dart';
import '../../menu/widgets/menu_item_image.dart';

/// First 6 displayable items for the home featured carousel — derived from
/// the already-loaded paginated menu cache (PERF-04). No duplicate first-page
/// fetch: home simply observes paginatedMenuProvider and filters locally.
final homeFeaturedProvider = Provider<List<MenuItem>>((ref) {
  final state = ref.watch(paginatedMenuProvider);
  final items = state.items;
  if (items.isEmpty) return const [];
  final available = items.where((i) => i.isAvailable).toList();
  final withPhoto = available
      .where((i) => i.imageUrl != null && i.imageUrl!.trim().isNotEmpty)
      .toList();
  final pool = withPhoto.length >= 4 ? withPhoto : available;
  return pool.take(6).toList();
});

class FeaturedCarousel extends ConsumerWidget {
  const FeaturedCarousel({
    super.key,
    required this.items,
    required this.strings,
  });

  final List<MenuItem> items;
  final HomeStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              strings.featuredTitle,
              style: AppTextStyles.titleMd.copyWith(color: AppColors.primary),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/menu'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.viewAllLabel,
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_left, size: 16, color: AppColors.secondary),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs8),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs8 + 2),
            itemBuilder: (context, index) {
              final item = items[index];
              return _FeaturedCard(item: item, lang: lang);
            },
          ),
        ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item, required this.lang});

  final MenuItem item;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final menuStrings = MenuStringsCatalog.of(lang);
    return SizedBox(
      width: 136,
      child: Material(
        color: AppColors.paperWhite,
        borderRadius:
            const BorderRadius.all(Radius.circular(AppRadii.lg16)),
        child: InkWell(
          borderRadius:
              const BorderRadius.all(Radius.circular(AppRadii.lg16)),
          onTap: () => showItemDetailSheet(context, item),
          child: Container(
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadii.lg16)),
              boxShadow: AppShadows.coffeeShadows(offset: const Offset(0, 4)),
            ),
            padding: const EdgeInsets.all(AppSpacing.xs8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MenuItemImage(item: item, width: 120, height: 88),
                const SizedBox(height: 6),
                Text(
                  item.name(lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.coffeeBean,
                  ),
                ),
                const Spacer(),
                Text(
                  menuStrings.price(item.priceEgp),
                  style: AppTextStyles.priceSm.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
