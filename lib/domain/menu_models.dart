// Pure menu models — canonical domain types for catalog + cart config.
// Mirrors Supabase `menu_categories` / `menu_items` (migration 0001).
// Domain-owned so cart_controller and pricing never import data.
// Data layer re-exports this file for backwards compat.
import '../core/l10n/app_strings.dart';

class MenuCategory {
  const MenuCategory({
    required this.slug,
    required this.nameAr,
    required this.nameEn,
  });

  final String slug;
  final String nameAr;
  final String nameEn;

  String name(AppLang lang) => lang == AppLang.ar ? nameAr : nameEn;
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.slug,
    required this.nameAr,
    required this.nameEn,
    required this.descAr,
    required this.descEn,
    required this.priceEgp,
    required this.isAvailable,
    required this.categorySlug,
    this.imageUrl,
  });

  final String id;
  final String slug;
  final String nameAr;
  final String nameEn;
  final String descAr;
  final String descEn;

  /// Whole EGP — prices are integers end-to-end (no POS, cash only).
  final int priceEgp;
  final String? imageUrl;
  final bool isAvailable;
  final String categorySlug;

  String name(AppLang lang) => lang == AppLang.ar ? nameAr : nameEn;
  String desc(AppLang lang) => lang == AppLang.ar ? descAr : descEn;
}

/// Per-item configuration chosen in the detail sheet.
///
/// Size carries a fixed price delta; sugar level is free; add-ons each carry a
/// fixed delta; the note is free-form and participates in cart-line identity.
class ItemConfig {
  const ItemConfig({
    this.sizeIndex = 0,
    this.sugarIndex = 0,
    this.addons = const <String>{},
    this.note,
  });

  static const sizeDeltasEgp = [0, 10, 15];

  static const addonPricesEgp = {
    'espresso_shot': 15,
    'caramel': 10,
    'whipped_cream': 12,
  };

  /// 0 small · 1 medium · 2 large.
  final int sizeIndex;

  /// 0 none · 1 little · 2 regular (free).
  final int sugarIndex;
  final Set<String> addons;
  final String? note;

  int get sizeDeltaEgp {
    if (sizeIndex < 0 || sizeIndex >= sizeDeltasEgp.length) {
      throw ArgumentError.value(sizeIndex, 'sizeIndex', 'must be 0..2');
    }
    return sizeDeltasEgp[sizeIndex];
  }

  int get addonsTotalEgp => addons.fold(
        0,
        (sum, id) => sum + (addonPricesEgp[id] ?? 0),
      );

  /// Stable identity for cart merging: same size + sugar + add-on set means
  /// "same config", regardless of set iteration order. Note is handled at the
  /// cart-line level so it stays part of line identity explicitly.
  String get identityKey =>
      's$sizeIndex|g$sugarIndex|a${(addons.toList()..sort()).join(',')}';

  ItemConfig copyWith({
    int? sizeIndex,
    int? sugarIndex,
    Set<String>? addons,
    String? note,
  }) {
    return ItemConfig(
      sizeIndex: sizeIndex ?? this.sizeIndex,
      sugarIndex: sugarIndex ?? this.sugarIndex,
      addons: addons ?? this.addons,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ItemConfig &&
        other.sizeIndex == sizeIndex &&
        other.sugarIndex == sugarIndex &&
        _setEquals(other.addons, addons) &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(
        sizeIndex,
        sugarIndex,
        Object.hashAllUnordered(addons),
        note,
      );

  static bool _setEquals(Set<String> a, Set<String> b) {
    return a.length == b.length && a.containsAll(b);
  }
}
