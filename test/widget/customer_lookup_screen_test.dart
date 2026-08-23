// Widget tests for the customer lookup screen (#013): the debounced search
// renders a fully-expanded profile card from a fake repo (tier chip, stats
// grid, recent orders), the manual reward grant flow updates the displayed
// points + fires the تمت الإضافة ✓ snackbar, and recent-search chips persist
// through mocked SharedPreferences (prefilled chip tap searches; a submitted
// term is written back to prefs). No network, no Supabase.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/customer_lookup_repository.dart';
import 'package:kady_app/data/repos/staff_orders_repository.dart';
import 'package:kady_app/ui/lookup/customer_lookup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCustomerLookupRepo implements CustomerLookupRepo {
  final searchedTerms = <String>[];
  final grantedRewards =
      <MapEntry<String, ManualRewardInput>>[];
  final visits = <CheckInInput>[];

  int points = 120;
  Object? grantError;

  @override
  Future<List<CustomerHit>> search(String term) async {
    searchedTerms.add(term);
    return [
      const CustomerHit(phone: '+201001234567', name: 'مصطفى كامل'),
    ];
  }

  @override
  Future<CustomerProfile> loadProfile(String phone) async =>
      CustomerProfile(
        phone: phone,
        name: 'مصطفى كامل',
        points: points,
        lifetimePoints: 1500,
        stamps: 3,
        visits: 7,
        recentOrders: [
          LookupOrder(
            createdAtUtc: DateTime.utc(2026, 8, 22, 10, 30),
            totalEgp: 95,
          ),
        ],
      );

  @override
  Future<void> grantManualReward(
    String phone,
    ManualRewardInput reward,
  ) async {
    final error = grantError;
    if (error != null) throw error;
    grantedRewards.add(MapEntry(phone, reward));
    points += 25; // the loyalty UPDATE lands → reload shows it
  }

  @override
  Future<VisitRecorded> registerVisit(CheckInInput input) async {
    visits.add(input);
    return const VisitRecorded(loyaltyPending: false);
  }

  @override
  Future<List<StaffActivity>> activityLog(String phone) async => const [];
}

Future<void> _pumpLookup(
  WidgetTester tester,
  _FakeCustomerLookupRepo repo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [customerLookupRepoProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CustomerLookupScreen(),
        ),
      ),
    ),
  );
  await tester.pump(); // recents provider future resolves
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('debounced search renders the expanded profile card from fake',
      (tester) async {
    await _pumpLookup(tester, _FakeCustomerLookupRepo());

    await tester.enterText(find.byType(TextField), 'مصطفى');
    await tester.pump(const Duration(milliseconds: 350)); // debounce fires
    await tester.pump(); // profile loads resolve

    // Identity row.
    expect(find.text('مصطفى كامل'), findsOneWidget);
    expect(find.text('+201001234567'), findsOneWidget);

    // Tier chip derived from lifetime points (1500 → برونزي).
    expect(find.text('برونزي'), findsOneWidget);

    // Stats grid values.
    expect(find.text('120'), findsOneWidget);
    expect(find.text('3 من 10'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);

    // Recent orders mini-list (Cairo dd/MM HH:mm + total).
    expect(find.text('آخر الطلبات'), findsOneWidget);
    expect(find.text('95 ج.م'), findsOneWidget);

    // Actions row.
    expect(find.text('إضافة مكافأة'), findsOneWidget);
    expect(find.text('تسجيل زيارة'), findsOneWidget);
  });

  testWidgets('grant flow credits points on the card + success snackbar',
      (tester) async {
    final repo = _FakeCustomerLookupRepo();
    await _pumpLookup(tester, repo);

    await tester.enterText(find.byType(TextField), 'مصطفى');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    await tester.tap(find.text('إضافة مكافأة'));
    await tester.pump(); // sheet route pushed
    await tester.pump(const Duration(milliseconds: 400)); // entrance done

    expect(find.text('إضافة مكافأة يدوية'), findsOneWidget);
    // Default selection: +25 نقطة radio pre-checked; confirm straight away.
    await tester.tap(find.widgetWithText(FilledButton, 'تأكيد الإضافة'));
    await tester.pump(); // grant resolves
    await tester.pump(); // sheet pops + reload starts
    await tester.pump(const Duration(milliseconds: 400)); // snackbar in

    expect(repo.grantedRewards.single.key, '+201001234567');
    expect(repo.grantedRewards.single.value.type, ManualRewardType.points25);

    // Reloaded card shows the credited balance.
    expect(find.text('145'), findsOneWidget);
    expect(find.text('تمت الإضافة ✓'), findsOneWidget);
  });

  testWidgets('recent chips persist via mocked prefs', (tester) async {
    SharedPreferences.setMockInitialValues({
      'lookup.recent': ['لاتيه'],
    });
    final repo = _FakeCustomerLookupRepo();
    await _pumpLookup(tester, repo);

    // Prefilled chip renders from prefs.
    expect(find.text('بحث سابق'), findsOneWidget);
    expect(find.text('لاتيه'), findsOneWidget);

    // Tap fills the field and searches immediately.
    await tester.tap(find.text('لاتيه'));
    await tester.pump();
    expect(repo.searchedTerms.last, 'لاتيه');

    // A submitted term is written back to the persisted list, newest first.
    await tester.enterText(find.byType(TextField), 'كابتشينو');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    final recents = prefs.getStringList('lookup.recent') ?? const [];
    expect(recents.first, 'كابتشينو');
    expect(recents, contains('لاتيه'));
  });
}
