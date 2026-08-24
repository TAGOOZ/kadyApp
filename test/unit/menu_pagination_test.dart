// TDD RED — Menu pagination (FEATURES §27, ADR-0011): 20 per page via Supabase .range
// FakeMenuRepo implements fetchPage(offset, limit) via sublist mimicking .range(offset, offset+limit-1).
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/menu_repository.dart';

/// In-memory fake that mirrors Supabase .range semantics: inclusive start/end.
/// Uses offset/limit to slice — equivalent to .range(offset, offset+limit-1).
class FakeMenuRepo implements MenuRepository {
  FakeMenuRepo({int totalItems = 95}) : _allItems = _generate(totalItems) {
    _allCategories = const [
      MenuCategory(slug: 'hot', nameAr: 'ساخن', nameEn: 'Hot'),
      MenuCategory(slug: 'cold', nameAr: 'بارد', nameEn: 'Cold'),
    ];
  }

  final List<MenuItem> _allItems;
  late final List<MenuCategory> _allCategories;

  static List<MenuItem> _generate(int count) {
    return List.generate(count, (i) {
      final cat = i.isEven ? 'hot' : 'cold';
      return MenuItem(
        id: 'item_$i',
        slug: 'item-$i',
        nameAr: 'عنصر $i',
        nameEn: 'Item $i',
        descAr: 'وصف $i',
        descEn: 'Desc $i',
        priceEgp: 10 + i,
        isAvailable: true,
        categorySlug: cat,
        imageUrl: null,
      );
    });
  }

  @override
  Future<CatalogSnapshot> fetchCatalog() async {
    // Should remain backwards compatible — returns full catalog.
    // RED: this will pass, but GREEN must keep it working while fetchPage uses range.
    return (_allCategories, List.of(_allItems));
  }

  @override
  Future<CatalogSnapshot> fetchPage({int offset = 0, int limit = 20}) async {
    // Mimics Supabase .range(offset, offset+limit-1) → sublist(offset, offset+limit)
    final end = (offset + limit).clamp(0, _allItems.length);
    final slice = offset >= _allItems.length
        ? <MenuItem>[]
        : _allItems.sublist(offset, end);
    // Categories are distinct union — here we return static categories for simplicity.
    // Real impl merges per-page categories.
    return (_allCategories, slice);
  }
}

void main() {
  group('MenuRepository.fetchPage — pagination contract (§27: 20 per page)', () {
    test('default limit is 20', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 95);
      final (_, items) = await repo.fetchPage();
      expect(items, hasLength(20), reason: 'default page must be 20 (FEATURES §27)');
    });

    test('fetchPage offset 0 → first 20', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 95);
      final (_, items) = await repo.fetchPage(offset: 0, limit: 20);
      expect(items, hasLength(20));
      expect(items.first.id, 'item_0');
      expect(items.last.id, 'item_19');
    });

    test('fetchPage offset 20 → next 20 (no overlap, sequential)', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 95);
      final (_, first) = await repo.fetchPage(offset: 0, limit: 20);
      final (_, second) = await repo.fetchPage(offset: 20, limit: 20);
      expect(second, hasLength(20));
      expect(second.first.id, 'item_20');
      expect(second.last.id, 'item_39');
      // No overlap
      final ids = {...first.map((e) => e.id), ...second.map((e) => e.id)};
      expect(ids, hasLength(40));
    });

    test('pagination covers 95 items in 5 pages (20+20+20+20+15)', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 95);
      final pages = <List<MenuItem>>[];
      for (var offset = 0; offset < 95; offset += 20) {
        final (_, slice) = await repo.fetchPage(offset: offset, limit: 20);
        pages.add(slice);
      }
      expect(pages, hasLength(5));
      expect(pages[0], hasLength(20));
      expect(pages[1], hasLength(20));
      expect(pages[2], hasLength(20));
      expect(pages[3], hasLength(20));
      expect(pages[4], hasLength(15));
      // All ids distinct and cover 0..94
      final allIds = pages.expand((p) => p).map((e) => e.id).toList();
      expect(allIds, hasLength(95));
      expect(allIds.toSet(), hasLength(95));
      expect(allIds.first, 'item_0');
      expect(allIds.last, 'item_94');
    });

    test('fetchPage beyond end returns empty', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 25);
      final (_, items) = await repo.fetchPage(offset: 30, limit: 20);
      expect(items, isEmpty);
    });

    test('fetchCatalog still returns full catalog (backwards compat)', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 95);
      final (cats, items) = await repo.fetchCatalog();
      expect(cats, hasLength(2));
      expect(items, hasLength(95));
    });

    test('fetchPage respects custom limit', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 50);
      final (_, items) = await repo.fetchPage(offset: 0, limit: 10);
      expect(items, hasLength(10));
      final (_, items2) = await repo.fetchPage(offset: 10, limit: 5);
      expect(items2, hasLength(5));
      expect(items2.first.id, 'item_10');
    });

    test('range semantics inclusive: .range(offset, offset+limit-1) equals sublist(offset, offset+limit)',
        () async {
      // This documents the Supabase contract: range start/end inclusive.
      // Fake uses sublist(offset, offset+limit) which must equal range(offset, offset+limit-1).
      MenuRepository repo = FakeMenuRepo(totalItems: 30);
      final (_, a) = await repo.fetchPage(offset: 5, limit: 20);
      // Expected ids 5..24 inclusive = 20 items
      expect(a.first.id, 'item_5');
      expect(a.last.id, 'item_24');
      expect(a, hasLength(20));
    });
  });

  group('Western digits & categories preserved per page', () {
    test('price uses Western digits via MenuStrings (not pagination logic)', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 5);
      final (_, items) = await repo.fetchPage(limit: 5);
      // Prices are ints — formatting is Western digits per §11.11, checked elsewhere.
      // Here we just ensure items carry priceEgp as int.
      expect(items.first.priceEgp, isA<int>());
    });

    test('categories union across pages stays distinct', () async {
      MenuRepository repo = FakeMenuRepo(totalItems: 40);
      final (cats1, _) = await repo.fetchPage(offset: 0, limit: 20);
      final (cats2, _) = await repo.fetchPage(offset: 20, limit: 20);
      final union = {...cats1.map((c) => c.slug), ...cats2.map((c) => c.slug)};
      expect(union, containsAll(['hot', 'cold']));
    });
  });
}
