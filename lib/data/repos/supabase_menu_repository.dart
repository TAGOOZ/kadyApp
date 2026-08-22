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

  @override
  Future<CatalogSnapshot> fetchCatalog() async {
    final rows = await _client
        .from('menu_items')
        .select('*, menu_categories(slug, name_ar, name_en, sort)')
        .order('sort', ascending: true);

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
