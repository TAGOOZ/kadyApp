// Home category shortcuts (#005 v2): horizontal pills mirroring the menu
// tab's category treatment — tap pre-selects the slug via
// selectedCategoryProvider and pushes /menu. Purely presentational; the
// catalog comes from homeCategoriesProvider (seam-overridable in tests).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/menu_models.dart';
import '../../../data/repos/supabase_menu_repository.dart';
import '../../menu/menu_screen.dart';

/// Categories for the home shortcuts (public read data, tiny table).
final homeCategoriesProvider = FutureProvider<List<MenuCategory>>((ref) async {
  return ref.watch(menuRepositoryProvider).fetchAllCategories();
});

class CategoryShortcuts extends ConsumerWidget {
  const CategoryShortcuts({
    super.key,
    required this.categories,
    required this.strings,
  });

  final List<MenuCategory> categories;
  final HomeStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.browseMenuTitle,
          style: AppTextStyles.titleMd.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.xs8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: categories.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: AppSpacing.xs8),
            itemBuilder: (context, index) {
              final category = categories[index];
              return _Pill(
                label: category.name(ref.watch(localeNotifierProvider)),
                onTap: () {
                  ref
                      .read(selectedCategoryProvider.notifier)
                      .select(category.slug);
                  context.push('/menu');
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm16),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
          border:
              Border.all(color: AppColors.outline.withValues(alpha: 0.25)),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.coffeeBean,
          ),
        ),
      ),
    );
  }
}
