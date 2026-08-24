// Menu tab (issue #002): sticky header + cart badge, category pills, item
// cards. Catalog loads via a FutureProvider over MenuRepository.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_menu.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/menu_models.dart';
import '../../data/repos/menu_repository.dart';
import '../../data/repos/supabase_menu_repository.dart';
import '../../domain/cart_controller.dart';
import '../widgets/bg_pattern.dart';
import 'item_detail_sheet.dart';
import 'widgets/menu_item_image.dart';

/// Whole-catalog snapshot; invalidated by the retry button on error.
final menuCatalogProvider = FutureProvider<CatalogSnapshot>((ref) async {
  return ref.watch(menuRepositoryProvider).fetchCatalog();
});

/// null = auto-select the first category once data arrives.
class SelectedCategoryNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? slug) => state = slug;
}

final selectedCategoryProvider =
    NotifierProvider<SelectedCategoryNotifier, String?>(
        SelectedCategoryNotifier.new);

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = AppStrings.of(lang);
    final menuStrings = MenuStringsCatalog.of(lang);
    final catalog = ref.watch(menuCatalogProvider);

    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: BgPattern(
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StickyHeader(menuTitle: strings.tabMenu, menuStrings: menuStrings),
            Expanded(
              child: catalog.when(
                loading: () => _LoadingShimmer(),
                error: (_, _) => _ErrorRetry(
                  message: menuStrings.errorTitle,
                  retryLabel: menuStrings.retry,
                ),
                data: (snapshot) => _CatalogList(
                  snapshot: snapshot,
                  lang: lang,
                  strings: menuStrings,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _StickyHeader extends ConsumerWidget {
  const _StickyHeader({required this.menuTitle, required this.menuStrings});

  final String menuTitle;
  final MenuStrings menuStrings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalQty = ref.watch(totalQuantityProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.margin20,
        AppSpacing.xs8,
        AppSpacing.sm16,
        AppSpacing.xs8,
      ),
      child: Row(
        children: [
          Text(
            menuTitle,
            style: AppTextStyles.headlineMobile
                .copyWith(color: AppColors.primary),
          ),
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: menuStrings.cartTooltip,
                onPressed: () => context.push('/cart'),
                icon: const Icon(Icons.shopping_cart_outlined),
              ),
              if (totalQty > 0)
                PositionedDirectional(
                  top: -2,
                  end: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: AppColors.secondaryContainer,
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadii.pill),
                      ),
                    ),
                    child: Text(
                      '$totalQty',
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.coffeeBean,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CatalogList extends ConsumerWidget {
  const _CatalogList({
    required this.snapshot,
    required this.lang,
    required this.strings,
  });

  final CatalogSnapshot snapshot;
  final AppLang lang;
  final MenuStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (categories, allItems) = snapshot;
    if (categories.isEmpty) {
      return Center(child: Text(strings.emptyCategoryLine));
    }

    final selected = ref.watch(selectedCategoryProvider);
    final effectiveSlug = categories.any((c) => c.slug == selected)
        ? selected!
        : categories.first.slug;
    final items =
        allItems.where((item) => item.categorySlug == effectiveSlug).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CategoryPills(
          categories: categories,
          lang: lang,
          activeSlug: effectiveSlug,
          onChanged: (slug) =>
              ref.read(selectedCategoryProvider.notifier).select(slug),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(strings.emptyCategoryLine))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter16,
                    AppSpacing.xs8,
                    AppSpacing.gutter16,
                    AppSpacing.lg32,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.xs8),
                  itemBuilder: (context, index) =>
                      _ItemCard(item: items[index], lang: lang),
                ),
        ),
      ],
    );
  }
}

class _CategoryPills extends StatelessWidget {
  const _CategoryPills({
    required this.categories,
    required this.lang,
    required this.activeSlug,
    required this.onChanged,
  });

  final List<MenuCategory> categories;
  final AppLang lang;
  final String activeSlug;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs8),
        itemBuilder: (context, index) {
          final category = categories[index];
          return _CategoryPill(
            label: category.name(lang),
            active: category.slug == activeSlug,
            onTap: () => onChanged(category.slug),
          );
        },
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
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
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm16),
        decoration: BoxDecoration(
          // Active chip = deep-forest fill, inactive = cream fill.
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

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.lang});

  final MenuItem item;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final strings = MenuStringsCatalog.of(lang);
    final body = Row(
      children: [
        MenuItemImage(item: item, width: 72, height: 72),
        const SizedBox(width: AppSpacing.xs8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                item.name(lang),
                style: AppTextStyles.titleSm,
              ),
              Text(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                item.nameEn,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              if (!item.isAvailable)
                Text(
                  strings.unavailableLabel,
                  style:
                      AppTextStyles.labelMd.copyWith(color: AppColors.error),
                )
              else
                Text(
                  // Orange IBM Plex price, Western digits.
                  strings.price(item.priceEgp),
                  style: AppTextStyles.priceSm.copyWith(
                     color: AppColors.secondary,
                   ),
                ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    );

    return Opacity(
      opacity: item.isAvailable ? 1 : 0.6,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md8),
          onTap: item.isAvailable
              ? () => showItemDetailSheet(context, item)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs8),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _LoadingShimmer extends StatefulWidget {
  @override
  State<_LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<_LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce-motion customers get a static skeleton — no pulsing.
    final animate = !MediaQuery.of(context).disableAnimations;

    Widget block(double height, {double? width}) {
      return FadeTransition(
        opacity: animate ? _opacity : const AlwaysStoppedAnimation(0.6),
        child: Container(
          height: height,
          width: width,
          decoration: const BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
          ),
        ),
      );
    }

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.gutter16),
      children: [
        Row(
          children: [
            block(36, width: 96),
            const SizedBox(width: AppSpacing.xs8),
            block(36, width: 120),
          ],
        ),
        for (var i = 0; i < 4; i++) ...[
          const SizedBox(height: AppSpacing.xs8),
          block(88),
        ],
      ],
    );
  }
}

class _ErrorRetry extends ConsumerWidget {
  const _ErrorRetry({required this.message, required this.retryLabel});

  final String message;
  final String retryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 40),
          const SizedBox(height: AppSpacing.xs8),
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyLg),
          const SizedBox(height: AppSpacing.sm16),
          FilledButton(
            onPressed: () => ref.invalidate(menuCatalogProvider),
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}
