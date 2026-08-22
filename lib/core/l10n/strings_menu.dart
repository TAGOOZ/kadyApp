// Menu slice strings catalog — mirrors the AppStrings pattern
// (`app_strings.dart` is intentionally NOT edited; this file owns all
// user-facing copy for the menu tab + item detail sheet).
// ar default, en toggle. Numerals: Western 0123 in both languages.
import 'app_strings.dart';

class MenuStrings {
  const MenuStrings({
    required this.menuTitle,
    required this.searchHint,
    required this.cartTooltip,
    required this.currencySuffix,
    required this.sizeLabel,
    required this.sizeNames,
    required this.sugarLabel,
    required this.sugarNames,
    required this.addonsLabel,
    required this.addonEspressoShot,
    required this.addonCaramel,
    required this.addonWhippedCream,
    required this.noteLabel,
    required this.noteHint,
    required this.qtyLabel,
    required this.addToCartPrefix,
    required this.unavailableLabel,
    required this.errorTitle,
    required this.retry,
    required this.emptyCategoryLine,
  });

  final String menuTitle;
  final String searchHint;
  final String cartTooltip;
  final String currencySuffix;
  final String sizeLabel;
  final List<String> sizeNames;
  final String sugarLabel;
  final List<String> sugarNames;
  final String addonsLabel;
  final String addonEspressoShot;
  final String addonCaramel;
  final String addonWhippedCream;
  final String noteLabel;
  final String noteHint;
  final String qtyLabel;

  /// Button label prefix; total is appended as `· {total} {suffix}`.
  final String addToCartPrefix;
  final String unavailableLabel;
  final String errorTitle;
  final String retry;
  final String emptyCategoryLine;

  /// Western digits everywhere (§11.11).
  String price(int valueEgp) => '$valueEgp $currencySuffix';

  String addonDelta(int deltaEgp) => '+$deltaEgp $currencySuffix';

  String addToCart(int lineTotalEgp) =>
      '$addToCartPrefix · $lineTotalEgp $currencySuffix';

  String addonName(String addonId) => switch (addonId) {
        'espresso_shot' => addonEspressoShot,
        'caramel' => addonCaramel,
        'whipped_cream' => addonWhippedCream,
        _ => addonId,
      };
}

abstract final class MenuStringsCatalog {
  static const Map<AppLang, MenuStrings> values = {
    AppLang.ar: MenuStrings(
      menuTitle: 'القائمة',
      searchHint: 'ابحث في القائمة',
      cartTooltip: 'السلة',
      currencySuffix: 'ج.م',
      sizeLabel: 'الحجم',
      sizeNames: ['صغير', 'وسط', 'كبير'],
      sugarLabel: 'السكر',
      sugarNames: ['بدون', 'قليل', 'عادي'],
      addonsLabel: 'إضافات',
      addonEspressoShot: 'شوت إسبريسو',
      addonCaramel: 'كراميل',
      addonWhippedCream: 'كريمة مخفوقة',
      noteLabel: 'ملاحظات خاصة',
      noteHint: 'مثال: ستيفايزر زيادة، بارد جداً…',
      qtyLabel: 'الكمية',
      addToCartPrefix: 'أضف للسلة',
      unavailableLabel: 'غير متوفر حالياً',
      errorTitle: 'تعذر تحميل القائمة',
      retry: 'إعادة المحاولة',
      emptyCategoryLine: 'لا توجد عناصر هنا بعد',
    ),
    AppLang.en: MenuStrings(
      menuTitle: 'Menu',
      searchHint: 'Search the menu',
      cartTooltip: 'Cart',
      currencySuffix: 'EGP',
      sizeLabel: 'Size',
      sizeNames: ['Small', 'Medium', 'Large'],
      sugarLabel: 'Sugar',
      sugarNames: ['None', 'Light', 'Regular'],
      addonsLabel: 'Extras',
      addonEspressoShot: 'Espresso shot',
      addonCaramel: 'Caramel',
      addonWhippedCream: 'Whipped cream',
      noteLabel: 'Special notes',
      noteHint: 'e.g. extra stevia, very cold…',
      qtyLabel: 'Qty',
      addToCartPrefix: 'Add to cart',
      unavailableLabel: 'Unavailable right now',
      errorTitle: "Couldn't load the menu",
      retry: 'Retry',
      emptyCategoryLine: 'Nothing here yet',
    ),
  };

  static MenuStrings of(AppLang lang) => values[lang]!;
}
