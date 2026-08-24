// Unsplash fallback for menu items where image_url is null.
// Deterministic mapping for the 12 category slugs seeded in
// supabase/migrations/0005_el_kady_menu.sql. Pure — no network, no widget.
import '../../data/models/menu_models.dart';

const _categoryKeywords = <String, String>{
  'turkish-coffee': 'turkish coffee',
  'espresso': 'espresso',
  'hot-drinks': 'hot coffee',
  'iced-espresso': 'iced coffee',
  'frappuccino': 'frappuccino',
  'desserts': 'dessert',
  'waffle': 'waffle',
  'fruit-salad': 'fruit salad',
  'ice-cream': 'ice cream',
  'bakery': 'bakery pastry',
  'extras': 'coffee',
  'winter-specials': 'hot chocolate',
};

/// Returns a deterministic Unsplash Source URL for [slug].
///
/// Example: `turkish-coffee` → `https://source.unsplash.com/400x400/?turkish%20coffee,coffee,cafe`
/// Unknown slugs fall back to the generic `coffee` keyword.
String unsplashUrlForCategory(String slug) {
  final keyword = _categoryKeywords[slug] ?? 'coffee';
  return 'https://source.unsplash.com/400x400/?${Uri.encodeComponent(keyword)},coffee,cafe';
}

/// Returns [item.imageUrl] when it is non-null and non-empty (after trim),
/// otherwise the category-based Unsplash fallback.
String unsplashUrlForItem(MenuItem item) {
  final url = item.imageUrl;
  if (url != null && url.trim().isNotEmpty) {
    return url;
  }
  return unsplashUrlForCategory(item.categorySlug);
}
