// Menu repository contract (issue #002).
// The catalog is public read data (RLS: anon AND authenticated), so no auth
// is required to fetch it.
import '../../data/models/menu_models.dart';

/// `(categories, items)` — one snapshot of the whole catalog.
typedef CatalogSnapshot = (List<MenuCategory>, List<MenuItem>);

abstract class MenuRepository {
  Future<CatalogSnapshot> fetchCatalog();
}
