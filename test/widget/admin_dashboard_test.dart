// Widget tests for the Admin dashboard (#015): tabs render from a fake db
// seam; availability switch hits the repo; rule edit dialog saves and calls
// refreshConfig on the loyalty controller; double_points note is visible;
// 42501-style denial shows the Arabic lock panel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/theme/app_theme.dart';
import 'package:kady_app/data/repos/admin_repositories.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
import 'package:kady_app/ui/admin/admin_dashboard_screen.dart';

import 'fake_admin_db.dart';

class _FixedLocale extends LocaleNotifier {
  @override
  AppLang build() => AppLang.ar;
}

class _RecordingLoyaltyController extends LoyaltyController {
  int refreshCount = 0;

  @override
  Future<void> refreshConfig() async {
    refreshCount++;
  }
}

Future<FakeAdminDb> seededDb() async {
  final db = FakeAdminDb();
  await db.loadJson({
    'campaigns': [
      {
        'id': 'c-1',
        'kind': 'double_points',
        'active': true,
        'name_ar': 'نقاط مضاعفة ليالي',
        'starts_at': null,
        'ends_at': null,
      },
      {
        'id': 'c-2',
        'kind': 'match_night',
        'active': false,
        'name_ar': null,
        'starts_at': null,
        'ends_at': null,
      },
    ],
    'menu_items': [
      {
        'id': 'm-1',
        'slug': 'latte',
        'category_id': 3,
        'menu_categories': {
          'id': 3,
          'slug': 'hot_drinks',
          'name_ar': 'مشروبات ساخنة',
          'name_en': 'Hot Drinks',
        },
        'name_ar': 'لاتيه',
        'name_en': 'Latte',
        'desc_ar': '',
        'desc_en': '',
        'price_egp': 45,
        'is_available': true,
        'sort': 1,
      },
      {
        'id': 'm-2',
        'slug': 'croissant',
        'category_id': 4,
        'menu_categories': {
          'id': 4,
          'slug': 'snacks',
          'name_ar': 'سناكس',
          'name_en': 'Snacks',
        },
        'name_ar': 'كرواسون',
        'name_en': 'Croissant',
        'desc_ar': '',
        'desc_en': '',
        'price_egp': 25,
        'is_available': false,
        'sort': 2,
      },
    ],
    'app_config': [
      {'key': 'points_per_10egp', 'value': 1},
      {'key': 'dine_in_multiplier', 'value': 1.1},
      {'key': 'stamp_min_spend', 'value': 50},
      {'key': 'redeem_min_points', 'value': 200},
      {'key': 'reward_topping', 'value': 100},
      {'key': 'reward_snack', 'value': 150},
      {'key': 'reward_drink', 'value': 200},
      {'key': 'delivery_fee', 'value': 15},
      {'key': 'tier_silver', 'value': 2000},
      {'key': 'tier_gold', 'value': 5000},
      {'key': 'rate_limit_max', 'value': 5},
      {'key': 'rate_limit_window_min', 'value': 5},
    ],
    'orders': [
      {
        'phone': '01000000001',
        'mode': 'dine_in',
        'subtotal': 90,
        'total': 99,
        'items': [
          {'name_ar': 'لاتيه', 'qty': 3},
        ],
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'phone': '01000000002',
        'mode': 'delivery',
        'subtotal': 120,
        'total': 135,
        'items': [
          {'name_ar': 'لاتيه', 'qty': 1},
          {'name_ar': 'كرواسون', 'qty': 2},
        ],
        'created_at': '2026-08-20T10:00:00Z',
      },
    ],
  });
  return db;
}

Widget wrapDashboard(FakeAdminDb db) {
  return ProviderScope(
    overrides: [
      adminDbProvider.overrideWithValue(db),
      localeNotifierProvider.overrideWith(_FixedLocale.new),
      loyaltyProvider.overrideWith(_RecordingLoyaltyController.new),
    ],
    child: MaterialApp(
      theme: buildHeritageHearth(Brightness.light),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: AdminDashboardScreen(),
      ),
    ),
  );
}

_RecordingLoyaltyController _recorderOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(AdminDashboardScreen)),
    ).read(loyaltyProvider.notifier) as _RecordingLoyaltyController;

Future<void> settleTabs(WidgetTester tester) async {
  await tester.pump(); // post-frame callbacks schedule the loads
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('shell renders header, KPI strip, tabs and staff-board chip',
      (tester) async {
    await tester.pumpWidget(wrapDashboard(await seededDb()));
    await settleTabs(tester);

    expect(find.text('لوحة الإدارة'), findsOneWidget);
    expect(find.text('لوحة الطلبات'), findsOneWidget);
    expect(find.text('طلبات اليوم'), findsOneWidget);
    expect(find.text('عملاء نشطون'), findsOneWidget);
    expect(find.text('متوسط السلة ج.م'), findsOneWidget);
    // KPI values are Western digits — 2 distinct phones today.
    expect(find.text('2'), findsWidgets);
    for (final tab in ['الحملات', 'القائمة', 'القواعد', 'التقارير']) {
      expect(find.text(tab), findsWidgets);
    }
  });

  testWidgets('campaigns tab shows kind labels, switch and double-points note',
      (tester) async {
    final db = await seededDb();
    await tester.pumpWidget(wrapDashboard(db));
    await settleTabs(tester);

    expect(find.text('نقاط مضاعفة ليالي'), findsOneWidget);
    // Unnamed match_night campaign title falls back to kind label — subtitle deduped (fix).
    expect(find.text('ليالي الماتشات'), findsOneWidget);
    // Active double_points campaign surfaces the immediate-application note.
    expect(find.text('يُطبّق على الطلبات الجديدة فورًا'), findsOneWidget);
    // FAB for new campaigns.
    expect(find.text('حملة جديدة'), findsOneWidget);
  });

  testWidgets('toggling a double_points campaign writes both payloads',
      (tester) async {
    final db = await seededDb();
    await tester.pumpWidget(wrapDashboard(db));
    await settleTabs(tester);

    // Toggle the active double_points campaign OFF.
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump(const Duration(milliseconds: 50));

    final update = db.ops.singleWhere(
      (op) => op.op == 'update' && op.table == 'campaigns',
    );
    expect(update.values, {'active': false});
    expect(update.whereValue, 'c-1');

    final flag = db.ops.singleWhere(
      (op) => op.op == 'upsert' && op.table == 'app_config',
    );
    expect(flag.values, {'key': 'double_window_active', 'value': false});
  });

  testWidgets('menu tab groups by category; availability switch hits repo',
      (tester) async {
    final db = await seededDb();
    await tester.pumpWidget(wrapDashboard(db));
    await settleTabs(tester);

    await goToTab(tester, 'القائمة');

    expect(find.text('مشروبات ساخنة'), findsOneWidget);
    expect(find.text('سناكس'), findsOneWidget);
    expect(find.text('لاتيه'), findsOneWidget);
    expect(find.text('45 ج.م'), findsOneWidget);

    // The latte is available=true → toggling calls setAvailability(false).
    final latteTile = find.ancestor(
      of: find.text('لاتيه'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: latteTile, matching: find.byType(Switch)),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final update = db.ops.singleWhere(
      (op) => op.op == 'update' && op.table == 'menu_items',
    );
    expect(update.values, {'is_available': false});
    expect(update.whereValue, 'm-1');
  });

  testWidgets('delete asks to confirm; undo re-inserts the previous row',
      (tester) async {
    final db = await seededDb();
    await tester.pumpWidget(wrapDashboard(db));
    await settleTabs(tester);

    await goToTab(tester, 'القائمة');
    await tester.longPress(find.text('كرواسون'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('حذف الصنف؟'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pump(const Duration(milliseconds: 100));

    final del = db.ops.singleWhere(
      (op) => op.op == 'delete' && op.table == 'menu_items',
    );
    expect(del.whereValue, 'm-2');

    // Snackbar offers تراجع → re-inserts the exact previous row.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('تراجع'));
    await tester.pump(const Duration(milliseconds: 100));

    final insert = db.ops.singleWhere(
      (op) => op.op == 'insert' && op.table == 'menu_items',
    );
    expect(insert.values['id'], 'm-2');
    expect(insert.values['slug'], 'croissant');
  });

  testWidgets('rule edit dialog saves jsonb value and refreshes loyalty config',
      (tester) async {
    final db = await seededDb();
    await tester.pumpWidget(wrapDashboard(db));
    await settleTabs(tester);

    await goToTab(tester, 'القواعد');

    expect(find.text('رسوم التوصيل (ج.م)'), findsOneWidget);
    expect(find.text('التيرات'), findsOneWidget);
    expect(find.text('حدود الحماية'), findsOneWidget);

    // The row sits below the fold — bring it into view first.
    await tester.ensureVisible(find.text('رسوم التوصيل (ج.م)'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('رسوم التوصيل (ج.م)'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).last, '20');
    await tester.tap(find.widgetWithText(FilledButton, 'حفظ'));
    await tester.pump(const Duration(milliseconds: 100));

    final save = db.ops.singleWhere(
      (op) => op.op == 'upsert' && op.values['key'] == 'delivery_fee',
    );
    expect(save.values['value'], 20);
    expect(save.onConflict, 'key');
    // The live loyalty engine picked up the new config.
    expect(_recorderOf(tester).refreshCount, 1);
  });

  testWidgets('reports tab renders mode share bars and aggregates',
      (tester) async {
    await tester.pumpWidget(wrapDashboard(await seededDb()));
    await settleTabs(tester);

    await goToTab(tester, 'التقارير');

    expect(find.text('صالة'), findsOneWidget);
    expect(find.text('استلام'), findsOneWidget);
    expect(find.text('توصيل'), findsOneWidget);
    expect(find.text('أعلى صنف مبيعًا'), findsOneWidget);
    // Top item across the window: لاتيه ×4.
    expect(find.text('لاتيه ×4'), findsOneWidget);
    // Mode percentages over 2 orders: dine_in 50%, pickup 0%, delivery 50%.
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('RLS denial shows the lock panel with retry', (tester) async {
    final db = FakeAdminDb()..denyReads = true;
    await tester.pumpWidget(wrapDashboard(db));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('بلا صلاحية مدير'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);

    // Retry keeps the panel while access is still denied.
    await tester.tap(find.text('إعادة المحاولة'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('بلا صلاحية مدير'), findsOneWidget);
  });
}
