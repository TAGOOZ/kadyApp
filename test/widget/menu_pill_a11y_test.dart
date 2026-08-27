// TDD: category pills must be accessible via InkWell with semantic tap (not GestureDetector).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/theme/app_theme.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/menu_repository.dart';
import 'package:kady_app/data/repos/supabase_menu_repository.dart';
import 'package:kady_app/ui/menu/menu_screen.dart';

class _FakeRepo implements MenuRepository {
  final cats = const [
    MenuCategory(slug: 'hot', nameAr: 'حار', nameEn: 'Hot'),
    MenuCategory(slug: 'snacks', nameAr: 'سناكس', nameEn: 'Snacks'),
  ];
  final items = List.generate(5, (i) => MenuItem(id: 'i_$i', slug: 'i-$i', nameAr: 'عنصر $i', nameEn: 'Item $i', descAr: '', descEn: '', priceEgp: 20, isAvailable: true, categorySlug: 'hot'));
  @override Future<CatalogSnapshot> fetchCatalog() async => (cats, items);
  @override Future<CatalogSnapshot> fetchPage({int offset=0,int limit=20}) async => (cats, items);
  @override Future<CatalogSnapshot> fetchPageByCategory({required String categorySlug,int offset=0,int limit=20}) async => (cats, items);
  @override Future<List<MenuCategory>> fetchAllCategories() async => cats;
}
class _FixedLocale extends LocaleNotifier { @override AppLang build() => AppLang.ar; }

void main() {
  testWidgets('category pills use InkWell with semantic label (a11y)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: [menuRepositoryProvider.overrideWithValue(_FakeRepo()), localeNotifierProvider.overrideWith(_FixedLocale.new)], child: MaterialApp(theme: buildHeritageHearth(Brightness.light), home: const Directionality(textDirection: TextDirection.rtl, child: MenuScreen()))),
    );
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
    // Pills should be InkWell (not GestureDetector) for heritage ripple + semantics
    final pillText = find.text('حار');
    expect(pillText, findsOneWidget);
    final inkWellAncestor = find.ancestor(of: pillText, matching: find.byType(InkWell));
    expect(inkWellAncestor, findsOneWidget, reason: 'pill حار must be inside InkWell (a11y)');
  });
}
