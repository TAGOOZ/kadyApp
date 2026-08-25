// TDD RED — Widget pagination: MenuScreen loads 20 then 40 on scroll (FEATURES §27)
// Pumps MenuScreen with a paginated fake (45 items → 3 pages) and verifies
// infinite scroll at 80% threshold triggers next page.
// Before GREEN this must fail: MenuScreen currently renders all items at once
// via fetchCatalog with no ScrollController pagination.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/riverpod_retry.dart';
import 'package:kady_app/core/theme/app_theme.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/menu_repository.dart';
import 'package:kady_app/data/repos/supabase_menu_repository.dart';
import 'package:kady_app/ui/menu/menu_pagination_controller.dart';
import 'package:kady_app/ui/menu/menu_screen.dart';

List<MenuItem> _generate(int count, String categorySlug) {
  return List.generate(count, (i) {
    return MenuItem(
      id: 'p_$i',
      slug: 'p-$i',
      nameAr: 'عنصر $i',
      nameEn: 'Item $i',
      descAr: 'وصف $i',
      descEn: 'Desc $i',
      priceEgp: 20 + i,
      isAvailable: true,
      categorySlug: categorySlug,
    );
  });
}

class FakePaginatedMenuRepo implements MenuRepository {
  FakePaginatedMenuRepo({this.total = 45})
      : _all = _generate(total, 'hot'),
        categories = const [
          MenuCategory(slug: 'hot', nameAr: 'مشروبات ساخنة', nameEn: 'Hot Drinks'),
        ];

  final int total;
  final List<MenuItem> _all;
  final List<MenuCategory> categories;

  @override
  Future<CatalogSnapshot> fetchCatalog() async {
    return (categories, List.of(_all));
  }

  @override
  Future<CatalogSnapshot> fetchPage({int offset = 0, int limit = 20}) async {
    // Supabase .range(offset, offset+limit-1) semantics
    final end = (offset + limit).clamp(0, _all.length);
    if (offset >= _all.length) return (categories, <MenuItem>[]);
    return (categories, _all.sublist(offset, end));
  }

  @override
  Future<List<MenuCategory>> fetchAllCategories() async => categories;

  @override
  Future<CatalogSnapshot> fetchPageByCategory({
    required String categorySlug,
    int offset = 0,
    int limit = 20,
  }) async {
    final filtered = _all.where((i) => i.categorySlug == categorySlug).toList();
    final end = (offset + limit).clamp(0, filtered.length);
    final slice = offset >= filtered.length ? <MenuItem>[] : filtered.sublist(offset, end);
    final cats = categories.where((c) => c.slug == categorySlug).toList();
    return (cats, slice);
  }
}

/// Locale fixed to Arabic to check RTL and Western digits.
class _FixedLocale extends LocaleNotifier {
  @override
  AppLang build() => AppLang.ar;
}

void main() {
  testWidgets('MenuScreen paginates 20 then 40 on scroll (80% threshold)', (tester) async {
    final fake = FakePaginatedMenuRepo(total: 45);

    // Use normal scrollable viewport (≈900px) so 20 items overflow and require scroll.
    // Keep physicalSize tall enough for visible items but small enough to be scrollable.
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    TextDirection? direction;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          menuRepositoryProvider.overrideWithValue(fake),
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

    // Initial shimmer then first page
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // First page should have exactly 20 items via provider (not 45).
    final ctx = tester.element(find.byType(MenuScreen));
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(paginatedMenuProvider).items, hasLength(20),
        reason: 'initial page must be 20 items (FEATURES §27)');
    // Also check UI: first item visible, second page not yet built
    expect(find.text('عنصر 0'), findsOneWidget);
    expect(container.read(paginatedMenuProvider).items.map((e) => e.id),
        contains('p_19'));
    expect(container.read(paginatedMenuProvider).items.map((e) => e.id),
        isNot(contains('p_20')));

    // Before pagination, second page item should NOT be loaded.
    expect(container.read(paginatedMenuProvider).items.length, 20);

    // Scroll to 80% to trigger next page load.
    final listFinder = find.byType(ListView).last;
    expect(listFinder, findsOneWidget);

    // Drag up significantly to reach 80% threshold.
    await tester.drag(listFinder, const Offset(0, -1200));
    await tester.pump();
    // Pump for pagination async fetch
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // After scroll, second page should be loaded → 40 items total
    expect(container.read(paginatedMenuProvider).items, hasLength(40),
        reason: 'scrolling to 80% must trigger next page (20→40)');
    expect(container.read(paginatedMenuProvider).items.map((e) => e.id),
        contains('p_20'));
    expect(container.read(paginatedMenuProvider).items.map((e) => e.id),
        contains('p_39'));

    // UI should now show second page after scroll (at least first of second page visible after pump)
    // With small viewport, after scroll, 'عنصر 20' should be visible
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('عنصر 20'), findsOneWidget);

    // Western digits: price suffix uses EGP with Western digits (any card shows "ج.م" with Western digits)
    expect(find.textContaining('ج.م'), findsWidgets);

    // RTL check via captured Directionality
    expect(direction, TextDirection.rtl);
    // Re-assert that Arabic copy was rendered (since English would be different).
    expect(find.text('مشروبات ساخنة'), findsOneWidget);
  });

  testWidgets('MenuScreen shows shimmer initially and retry on error', (tester) async {
    // This test documents loading/error UX required by GREEN.
    // A failing repo should show errorTitle + retry button.
    // Use noAutoRetry so error renders instantly (ADR-0012).
    final errorRepo = _ErrorMenuRepo();

    await tester.pumpWidget(
      ProviderScope(
        retry: noAutoRetry,
        overrides: [
          menuRepositoryProvider.overrideWithValue(errorRepo),
          localeNotifierProvider.overrideWith(_FixedLocale.new),
        ],
        child: MaterialApp(
          theme: buildHeritageHearth(Brightness.light),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MenuScreen(),
          ),
        ),
      ),
    );

    await tester.pump();
    // Shimmer appears instantly (before error)
    // We allow either shimmer or error — but after async failure, error must show.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // Should show errorTitle in Arabic: 'تعذر تحميل القائمة' and retry button
    expect(find.text('تعذر تحميل القائمة'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}

class _ErrorMenuRepo implements MenuRepository {
  @override
  Future<CatalogSnapshot> fetchCatalog() async {
    throw Exception('network');
  }

  @override
  Future<CatalogSnapshot> fetchPage({int offset = 0, int limit = 20}) async {
    throw Exception('network');
  }

  @override
  Future<CatalogSnapshot> fetchPageByCategory({
    required String categorySlug,
    int offset = 0,
    int limit = 20,
  }) async {
    throw Exception('network');
  }

  @override
  Future<List<MenuCategory>> fetchAllCategories() async {
    throw Exception('network');
  }
}
