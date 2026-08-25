// Supabase-backed menu repository — reads the public catalog via a single
// embedded query (`menu_items` joined to `menu_categories`), per issue #002.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../models/menu_models.dart';
import 'menu_repository.dart';

final menuRepositoryProvider = Provider<MenuRepository>((ref) {
  return SupabaseMenuRepository(supabase);
});

class SupabaseMenuRepository implements MenuRepository {
  SupabaseMenuRepository(this._client);

  final SupabaseClient _client;

  /// Paginated fetch via Supabase `.range(offset, offset+limit-1)` (inclusive).
  /// 20 per page per FEATURES §27.
  @override
  Future<CatalogSnapshot> fetchPage({int offset = 0, int limit = 20}) async {
    final rows = await _client
        .from('menu_items')
        .select('*, menu_categories(slug, name_ar, name_en, sort)')
        .order('sort', ascending: true)
        .range(offset, offset + limit - 1);
    return _parseRows(rows);
  }

  @override
  Future<CatalogSnapshot> fetchPageByCategory({
    required String categorySlug,
    int offset = 0,
    int limit = 20,
  }) async {
    final rows = await _client
        .from('menu_items')
        .select('*, menu_categories!inner(slug, name_ar, name_en, sort)')
        .eq('menu_categories.slug', categorySlug)
        .order('sort', ascending: true)
        .range(offset, offset + limit - 1);
    return _parseRows(rows);
  }

  @override
  Future<List<MenuCategory>> fetchAllCategories() async {
    final rows = await _client
        .from('menu_categories')
        .select('slug, name_ar, name_en, sort')
        .order('sort', ascending: true);
    return [
      for (final row in List<Map<String, dynamic>>.from(rows as List))
        MenuCategory(
          slug: row['slug'] as String,
          nameAr: (row['name_ar'] as String?) ?? row['slug'] as String,
          nameEn: (row['name_en'] as String?) ?? row['slug'] as String,
        ),
    ];
  }

  @override
  Future<CatalogSnapshot> fetchCatalog() async {
    // Backwards compat: fetch all via paginated range internally.
    // Keeps contract while honoring §27 pagination (uses range).
    const chunk = 20;
    var offset = 0;
    final allCategories = <String, MenuCategory>{};
    final allItems = <MenuItem>[];
    while (true) {
      final (cats, items) = await fetchPage(offset: offset, limit: chunk);
      for (final c in cats) {
        allCategories.putIfAbsent(c.slug, () => c);
      }
      allItems.addAll(items);
      if (items.length < chunk) break;
      offset += chunk;
      // Safety: if catalog is huge, cap at reasonable upper bound to avoid infinite loop.
      if (offset > 10000) break;
    }
    final sortedCategories = allCategories.values.toList()
      ..sort((a, b) => a.slug.compareTo(b.slug));
    return (sortedCategories, allItems);
  }

  CatalogSnapshot _parseRows(dynamic rows) {
    // Shared parser for fetchPage/fetchCatalog range results.

    final categories = <String, MenuCategory>{};
    final items = <MenuItem>[];

    for (final row in List<Map<String, dynamic>>.from(rows as List)) {
      final categoryData = row['menu_categories'];
      if (categoryData is! Map<String, dynamic>) {
        // Items without a category are not browsable — skip this slice.
        continue;
      }
      final slug = categoryData['slug'] as String?;
      if (slug == null) continue;

      categories.putIfAbsent(
        slug,
        () => MenuCategory(
          slug: slug,
          nameAr: (categoryData['name_ar'] as String?) ?? slug,
          nameEn: (categoryData['name_en'] as String?) ?? slug,
        ),
      );

      items.add(
        MenuItem(
          id: row['id'] as String,
          slug: row['slug'] as String? ?? '',
          nameAr: (row['name_ar'] as String?) ?? '',
          nameEn: (row['name_en'] as String?) ?? '',
          descAr: (row['desc_ar'] as String?) ?? '',
          descEn: (row['desc_en'] as String?) ?? '',
          priceEgp: (row['price_egp'] as num?)?.toInt() ?? 0,
          imageUrl: row['image_url'] as String?,
          isAvailable: (row['is_available'] as bool?) ?? true,
          categorySlug: slug,
        ),
      );
    }

    final sortedCategories =
        categories.values.toList()..sort((a, b) => a.slug.compareTo(b.slug));
    return (sortedCategories, items);
  }
}
