// Menu tab — paginated infinite scroll 20 per page (FEATURES §27, ADR-0011).
// Catalog loads via paginated StateNotifier over MenuRepository.fetchPage(offset, limit)
// using Supabase .range(offset, offset+limit-1). Keeps legacy menuCatalogProvider
// for backwards compat (now delegates to paginated fetch via fetchCatalog).
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
import 'item_detail_sheet.dart';
import 'menu_pagination_controller.dart';
import 'widgets/menu_item_image.dart';

/// Whole-catalog snapshot; invalidated by the retry button on error.
/// Kept for backwards compat — still works but internally uses range pagination
/// (SupabaseMenuRepository.fetchCatalog now loops via fetchPage).
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

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Guard: no scrollable extent yet (short list)
    if (position.maxScrollExtent == 0) return;
    // 80% threshold per spec: detect 80% scroll to trigger next page.
    if (position.pixels >= position.maxScrollExtent * 0.8) {
      final state = ref.read(paginatedMenuProvider);
      if (!state.isLoading &&
          !state.isLoadingMore &&
          state.hasMore &&
          state.error == null) {
        ref.read(paginatedMenuProvider.notifier).loadNext();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = AppStrings.of(lang);
    final menuStrings = MenuStringsCatalog.of(lang);
    final paginated = ref.watch(paginatedMenuProvider);

    Widget body;
    if (paginated.isLoading && paginated.items.isEmpty) {
      body = _LoadingShimmer();
    } else if (paginated.error != null && paginated.items.isEmpty) {
      body = _ErrorRetry(
        message: menuStrings.errorTitle,
        retryLabel: menuStrings.retry,
        onRetry: () => ref.read(paginatedMenuProvider.notifier).retry(),
      );
    } else {
      body = _PaginatedCatalogList(
        state: paginated,
        lang: lang,
        strings: menuStrings,
        scrollController: _scrollController,
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            _StickyHeader(menuTitle: strings.tabMenu, menuStrings: menuStrings),
            Expanded(child: body),
          ],
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

/// Paginated catalog list — keeps SelectedCategory filtering per page,
/// shows shimmer while loading more, and retry on error.
class _PaginatedCatalogList extends ConsumerWidget {
  const _PaginatedCatalogList({
    required this.state,
    required this.lang,
    required this.strings,
    required this.scrollController,
  });

  final PaginatedMenuState state;
  final AppLang lang;
  final MenuStrings strings;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = state.categories;
    final allItems = state.items;

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
              : Stack(
                  children: [
                    ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.gutter16,
                        AppSpacing.xs8,
                        AppSpacing.gutter16,
                        AppSpacing.lg32,
                      ),
                      itemCount: items.length + 1,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.xs8),
                      itemBuilder: (context, index) {
                        if (index == items.length) {
                          // Bottom loader / retry / hasMore sentinel.
                          if (state.isLoadingMore) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          if (state.error != null) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs8),
                              child: Center(
                                child: FilledButton(
                                  onPressed: () => ref
                                      .read(paginatedMenuProvider.notifier)
                                      .retry(),
                                  child: Text(strings.retry),
                                ),
                              ),
                            );
                          }
                          // No more or not loading — empty sentinel to keep scroll physics stable.
                          return const SizedBox(height: AppSpacing.xs8);
                        }
                        return _ItemCard(item: items[index], lang: lang);
                      },
                    ),
                    // Top shimmer is handled by parent; inline error banner if paginated error with data
                    if (state.error != null && state.items.isNotEmpty && !state.isLoadingMore)
                      Positioned(
                        left: AppSpacing.gutter16,
                        right: AppSpacing.gutter16,
                        bottom: AppSpacing.xs8,
                        child: _InlineError(
                          message: strings.errorTitle,
                          onRetry: () => ref.read(paginatedMenuProvider.notifier).retry(),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs8),
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius: BorderRadius.circular(AppRadii.md8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        boxShadow: AppShadows.coffeeShadows(),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: AppSpacing.xs8),
          Expanded(child: Text(message, style: AppTextStyles.bodySm)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
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
  const _ErrorRetry(
      {required this.message, required this.retryLabel, this.onRetry});

  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

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
            onPressed: onRetry ??
                () {
                  // Default: invalidate both providers for back-compat
                  ref.invalidate(menuCatalogProvider);
                  ref.invalidate(paginatedMenuProvider);
                },
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}
