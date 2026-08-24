// Menu repository contract (issue #002, §27 pagination).
// The catalog is public read data (RLS: anon AND authenticated), so no auth
// is required to fetch it.
// Pagination via Supabase .range(offset, offset+limit-1) — 20 per page (FEATURES §27).
import '../../data/models/menu_models.dart';

/// `(categories, items)` — one snapshot of the whole catalog.
typedef CatalogSnapshot = (List<MenuCategory>, List<MenuItem>);

abstract class MenuRepository {
  Future<CatalogSnapshot> fetchCatalog();

  /// Paginated slice via Supabase `.range(offset, offset+limit-1)` (inclusive).
  /// Default 20 per page per FEATURES §27 (Lists: paginated infinite scroll 20).
  Future<CatalogSnapshot> fetchPage({int offset = 0, int limit = 20});

  /// All categories (12) — used to render filter pills before items are fully
  /// paginated. Categories are tiny (id, slug, names) so loading all at once
  /// is cheap and fixes "filters not all shown" when first page only has 2-3 cats.
  Future<List<MenuCategory>> fetchAllCategories();
}
