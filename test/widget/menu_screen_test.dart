// Widget test for the menu tab (issue #002): category chips + item cards
// render from an overridden repository — no live network.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/theme/app_theme.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/menu_repository.dart';
import 'package:kady_app/data/repos/supabase_menu_repository.dart';
import 'package:kady_app/ui/menu/menu_screen.dart';

class FakeMenuRepository implements MenuRepository {
  @override
  Future<CatalogSnapshot> fetchCatalog() async {
    const categories = [
      MenuCategory(slug: 'hot', nameAr: 'مشروبات ساخنة', nameEn: 'Hot Drinks'),
      MenuCategory(slug: 'cold', nameAr: 'مشروبات باردة', nameEn: 'Cold Drinks'),
    ];
    final items = [
      const MenuItem(
        id: 'latte',
        slug: 'latte',
        nameAr: 'لاتيه',
        nameEn: 'Latte',
        descAr: 'حليب وإسبريسو',
        descEn: 'Milk and espresso',
        priceEgp: 45,
        isAvailable: true,
        categorySlug: 'hot',
      ),
      const MenuItem(
        id: 'iced-tea',
        slug: 'iced-tea',
        nameAr: 'شاي مثلج',
        nameEn: 'Iced Tea',
        descAr: 'شاي بالليمون',
        descEn: 'Lemon tea',
        priceEgp: 30,
        isAvailable: true,
        categorySlug: 'cold',
      ),
    ];
    return (categories, items);
  }

  @override
  Future<CatalogSnapshot> fetchPage({int offset = 0, int limit = 20}) async {
    final (cats, items) = await fetchCatalog();
    final end = (offset + limit).clamp(0, items.length);
    if (offset >= items.length) return (cats, <MenuItem>[]);
    return (cats, items.sublist(offset, end));
  }

  @override
  Future<List<MenuCategory>> fetchAllCategories() async {
    final (cats, _) = await fetchCatalog();
    return cats;
  }

  @override
  Future<CatalogSnapshot> fetchPageByCategory({
    required String categorySlug,
    int offset = 0,
    int limit = 20,
  }) async {
    final (cats, items) = await fetchCatalog();
    final filtered = items.where((i) => i.categorySlug == categorySlug).toList();
    final end = (offset + limit).clamp(0, filtered.length);
    final slice = offset >= filtered.length ? <MenuItem>[] : filtered.sublist(offset, end);
    final cat = cats.where((c) => c.slug == categorySlug).toList();
    return (cat, slice);
  }
}

void main() {
  testWidgets('menu renders category chips, item cards and RTL Arabic copy',
      (tester) async {
    TextDirection? direction;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          menuRepositoryProvider.overrideWithValue(FakeMenuRepository()),
          localeNotifierProvider.overrideWith(_FixedLocale.new),
        ],
        child: MaterialApp(
          theme: buildHeritageHearth(Brightness.light),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) {
                direction = Directionality.of(context);
                return const MenuScreen();
              },
            ),
          ),
        ),
      ),
    );

    // First frame = shimmer; second resolves the fake future.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(direction, TextDirection.rtl);

    // Category chip (AR-first).
    expect(find.text('مشروبات ساخنة'), findsOneWidget);
    // Item card: AR name + EN subtitle + orange price with Western digits.
    expect(find.text('لاتيه'), findsOneWidget);
    expect(find.text('Latte'), findsOneWidget);
    expect(find.text('45 ج.م'), findsOneWidget);
  });
}

class _FixedLocale extends LocaleNotifier {
  @override
  AppLang build() => AppLang.ar;
}
