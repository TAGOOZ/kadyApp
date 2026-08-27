// TDD tracer: menu pills preserve DB sort order after pagination (regression for slug-sort bug).
// Public interface: PaginatedMenuNotifier via menuRepositoryProvider.
// Behavior: fetchAllCategories returns DB-ordered [snacks, hot, cold]; after loadNext, order must stay [snacks, hot, cold] not alphabetical [cold, hot, snacks].
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/menu_repository.dart';
import 'package:kady_app/data/repos/supabase_menu_repository.dart';
import 'package:kady_app/ui/menu/menu_pagination_controller.dart';

class _OrderFakeRepo implements MenuRepository {
  // DB order deliberately not alphabetical: snacks, hot, cold (alphabetical would be cold, hot, snacks)
  final List<MenuCategory> dbOrder = const [
    MenuCategory(slug: 'snacks', nameAr: 'سناكس', nameEn: 'Snacks'),
    MenuCategory(slug: 'hot', nameAr: 'حار', nameEn: 'Hot'),
    MenuCategory(slug: 'cold', nameAr: 'بارد', nameEn: 'Cold'),
  ];

  final List<MenuItem> _hotPage = List.generate(20, (i) => MenuItem(
        id: 'hot_$i',
        slug: 'hot-$i',
        nameAr: 'حار $i',
        nameEn: 'Hot $i',
        descAr: '',
        descEn: '',
        priceEgp: 20,
        isAvailable: true,
        categorySlug: 'hot',
      ));
  final List<MenuItem> _coldPage = List.generate(20, (i) => MenuItem(
        id: 'cold_$i',
        slug: 'cold-$i',
        nameAr: 'بارد $i',
        nameEn: 'Cold $i',
        descAr: '',
        descEn: '',
        priceEgp: 20,
        isAvailable: true,
        categorySlug: 'cold',
      ));

  @override
  Future<CatalogSnapshot> fetchCatalog() async => (dbOrder, [..._hotPage, ..._coldPage]);

  @override
  Future<CatalogSnapshot> fetchPage({int offset = 0, int limit = 20}) async {
    // Simulate Supabase .range returning items slice; categories derived sorted by slug (bug source).
    // First page returns hot, second returns cold.
    if (offset == 0) {
      // _parseRows sorts by slug -> [hot]
      return ([dbOrder[1]], _hotPage);
    } else {
      return ([dbOrder[2]], _coldPage);
    }
  }

  @override
  Future<CatalogSnapshot> fetchPageByCategory({required String categorySlug, int offset = 0, int limit = 20}) async {
    final cats = dbOrder.where((c) => c.slug == categorySlug).toList();
    final items = categorySlug == 'hot' ? _hotPage : _coldPage;
    return (cats, items);
  }

  @override
  Future<List<MenuCategory>> fetchAllCategories() async => dbOrder;
}

void main() {
  test('pills order stays DB sort after loadNext (not slug alphabetical)', () async {
    final repo = _OrderFakeRepo();
    final container = ProviderContainer(overrides: [
      menuRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(paginatedMenuProvider.notifier);
    // Wait initial load
    await Future.delayed(const Duration(milliseconds: 100));
    await container.read(paginatedMenuProvider.notifier).stream.firstWhere((s) => !s.isLoading).timeout(const Duration(seconds: 1), onTimeout: () => container.read(paginatedMenuProvider));
    // Alternative: pump until loaded
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!container.read(paginatedMenuProvider).isLoading) break;
    }

    final initialCats = container.read(paginatedMenuProvider).categories.map((c) => c.slug).toList();
    expect(initialCats, ['snacks', 'hot', 'cold'], reason: 'initial must be DB order');

    // Trigger loadNext (second page cold)
    await notifier.loadNext();
    await Future.delayed(const Duration(milliseconds: 50));
    final afterCats = container.read(paginatedMenuProvider).categories.map((c) => c.slug).toList();
    // BUG: current code sorts by slug -> [cold, hot, snacks] but should stay [snacks, hot, cold]
    expect(afterCats, ['snacks', 'hot', 'cold'], reason: 'after loadNext order must remain DB sort, not alphabetical');
  });
}
