// Menu editor repository (#015, ARCH-02 split): AdminCategory / AdminMenuItem CRUD.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_db.dart';

class AdminCategory {
  const AdminCategory({
    required this.id,
    required this.slug,
    required this.nameAr,
    required this.nameEn,
  });

  final int id;
  final String slug;
  final String nameAr;
  final String nameEn;
}

/// Editable mirror of a `menu_items` row (joined category).
class AdminMenuItem {
  const AdminMenuItem({
    required this.id,
    required this.slug,
    required this.nameAr,
    required this.nameEn,
    required this.descAr,
    required this.descEn,
    required this.priceEgp,
    required this.isAvailable,
    required this.sort,
    this.categoryId,
    this.categorySlug,
    this.categoryNameAr,
    this.imageUrl,
  });

  final String id;
  final String slug;
  final String nameAr;
  final String nameEn;
  final String descAr;
  final String descEn;
  final int priceEgp;
  final bool isAvailable;
  final int sort;
  final int? categoryId;
  final String? categorySlug;
  final String? categoryNameAr;
  final String? imageUrl;

  factory AdminMenuItem.fromRow(Map<String, dynamic> row) {
    final category = row['menu_categories'];
    int? categoryId;
    String? categorySlug;
    String? categoryNameAr;
    if (category is Map) {
      categoryId = (category['id'] as num?)?.toInt();
      categorySlug = category['slug'] as String?;
      categoryNameAr = (category['name_ar'] as String?) ?? categorySlug;
    }
    return AdminMenuItem(
      id: row['id'] as String,
      slug: (row['slug'] as String?) ?? '',
      nameAr: (row['name_ar'] as String?) ?? '',
      nameEn: (row['name_en'] as String?) ?? '',
      descAr: (row['desc_ar'] as String?) ?? '',
      descEn: (row['desc_en'] as String?) ?? '',
      priceEgp: (row['price_egp'] as num?)?.toInt() ?? 0,
      isAvailable: (row['is_available'] as bool?) ?? true,
      sort: (row['sort'] as num?)?.toInt() ?? 0,
      categoryId: categoryId,
      categorySlug: categorySlug,
      categoryNameAr: categoryNameAr,
      imageUrl: row['image_url'] as String?,
    );
  }

  /// Full-row payload — also reused verbatim for delete-undo re-insertion.
  Map<String, dynamic> toPayload() => {
        'id': id,
        'slug': slug,
        'name_ar': nameAr,
        'name_en': nameEn,
        'desc_ar': descAr,
        'desc_en': descEn,
        'price_egp': priceEgp,
        'is_available': isAvailable,
        'sort': sort,
        'category_id': ?categoryId,
        'image_url': ?imageUrl,
      };
}

/// Form values collected by the menu editor sheet.
class MenuItemDraft {
  const MenuItemDraft({
    required this.slug,
    required this.nameAr,
    required this.nameEn,
    required this.descAr,
    required this.descEn,
    required this.priceEgp,
    required this.categoryId,
    required this.sort,
    this.imageUrl,
  });

  final String slug;
  final String nameAr;
  final String nameEn;
  final String descAr;
  final String descEn;
  final int priceEgp;
  final int categoryId;
  final int sort;
  final String? imageUrl;
}

class AdminMenuRepository {
  const AdminMenuRepository(this._db);

  final AdminDbClient _db;

  Future<({List<AdminCategory> categories, List<AdminMenuItem> items})>
      listCatalog() async {
    final rows = await readOrEmpty(
      () => _db.select(
        'menu_items',
        columns: '*, menu_categories(id, slug, name_ar, name_en)',
        orderBy: 'sort',
      ),
    );
    final categories = <int, AdminCategory>{};
    final items = <AdminMenuItem>[];
    for (final row in rows) {
      final item = AdminMenuItem.fromRow(row);
      final catId = item.categoryId;
      final rawCat = row['menu_categories'];
      if (catId != null &&
          !categories.containsKey(catId) &&
          rawCat is Map &&
          rawCat['slug'] is String) {
        categories[catId] = AdminCategory(
          id: catId,
          slug: rawCat['slug'] as String,
          nameAr: (rawCat['name_ar'] as String?) ?? rawCat['slug'] as String,
          nameEn: (rawCat['name_en'] as String?) ?? rawCat['slug'] as String,
        );
      }
      items.add(item);
    }
    final sortedCategories = categories.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return (categories: sortedCategories, items: items);
  }

  /// Insert (new item) or update ([id] present). Slug must be unique —
  /// callers generate one via [generateSlug] for inserts.
  Future<void> upsertItem(MenuItemDraft draft, {String? id}) async {
    await _db.upsert('menu_items', {
      'id': ?id,
      'slug': draft.slug,
      'category_id': draft.categoryId,
      'name_ar': draft.nameAr,
      'name_en': draft.nameEn,
      'desc_ar': draft.descAr,
      'desc_en': draft.descEn,
      'price_egp': draft.priceEgp,
      'sort': draft.sort,
      'image_url': ?draft.imageUrl,
    });
  }

  Future<void> setAvailability(String id, bool available) async {
    await _db.update(
      'menu_items',
      {'is_available': available},
      whereColumn: 'id',
      whereValue: id,
    );
  }

  Future<void> deleteItem(String id) async {
    await _db.delete('menu_items', whereColumn: 'id', whereValue: id);
  }

  /// Undo path for deletes: re-inserts the exact previous row (same uuid).
  Future<void> reinsertRow(Map<String, dynamic> fullRow) async {
    await _db.insert('menu_items', fullRow);
  }

  /// Unique-enough slug for new items: EN-name slugified + timestamp tail
  /// (the column is NOT NULL UNIQUE).
  static String generateSlug(String nameEn) {
    final base = nameEn
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final salt = _slugSeq = (_slugSeq + 1) & 0xFFF;
    return '${base.isEmpty ? 'item' : base}-$stamp$salt';
  }

  static int _slugSeq = 0;
}

final adminMenuRepositoryProvider = Provider<AdminMenuRepository>(
  (ref) => AdminMenuRepository(ref.watch(adminDbProvider)),
);
