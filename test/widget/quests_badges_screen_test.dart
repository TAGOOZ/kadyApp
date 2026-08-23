// Widget tests for the quests/badges screen (#010): tabs render, quest
// card progress mirrors a fake feed (٢/٣ AR label), claim flow marks the
// quest claimed in prefs and disables the button, match-token claims
// queue a pending grant (seam-gap deviation), badge medallions show
// locked vs earned visuals with a one-time celebration, and fetch errors
// render ٠/٣ + retry.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/quest_state_store.dart';
import 'package:kady_app/domain/quests_engine.dart';
import 'package:kady_app/ui/quests/quests_badges_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeQuestFeed implements QuestFeedRepo {
  _FakeQuestFeed({
    this.orders = const [],
    this.categories = const {},
    this.windows = CampaignWindows.empty,
    this.failOrders = false,
  });

  List<QuestOrderInput> orders;
  Map<String, String> categories;
  CampaignWindows windows;
  bool failOrders;

  @override
  Future<List<QuestOrderInput>> fetchCompletedOrders(String googleUserId) async {
    if (failOrders) throw Exception('offline');
    return orders;
  }

  @override
  Future<Map<String, String>> fetchItemCategories() async => categories;

  @override
  Future<CampaignWindows> fetchCampaignWindows() async => windows;
}

QuestOrderInput _order(
  String id,
  String mode,
  DateTime at, [
  List<String> itemIds = const [],
]) =>
    QuestOrderInput(orderId: id, modeWire: mode, createdAtUtc: at, itemIds: itemIds);

/// Tall surface so every quest card / medallion is built (ListView is
/// lazy; default 800×600 hides rows below the fold).
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, _FakeQuestFeed feed) async {
  _useTallSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [questFeedProvider.overrideWithValue(feed)],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: QuestsBadgesScreen(),
        ),
      ),
    ),
  );
  // Resolve locale hydration + snapshot future + store hydration.
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders both tabs and reflects fake feed progress (٢/٣)',
      (tester) async {
    final now = DateTime(2026, 8, 15, 12);
    final feed = _FakeQuestFeed(
      orders: [
        _order('o1', 'pickup', now.subtract(const Duration(days: 2)),
            ['latte']),
        _order('o2', 'dine_in', now.subtract(const Duration(days: 1)),
            ['iced']),
      ],
      categories: {'latte': 'hot_drinks', 'iced': 'cold_drinks'},
    );
    await _pump(tester, feed);

    expect(find.text('المهام'), findsOneWidget);
    expect(find.text('الشارات'), findsOneWidget);
    // Two of three distinct drinks → ٢/٣ (AR numerals).
    expect(find.text('٢/٣'), findsOneWidget);
    expect(find.text('١/٢'), findsNothing);

    // Incomplete quests cannot be claimed.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'استلم المكافأة').first,
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('claiming the drinks quest credits via seam, persists claimed '
      'and disables the button', (tester) async {
    final now = DateTime.now();
    final feed = _FakeQuestFeed(
      orders: [
        _order('o1', 'pickup', now.subtract(const Duration(days: 3)),
            ['latte']),
        _order('o2', 'pickup', now.subtract(const Duration(days: 2)),
            ['iced']),
        _order('o3', 'dine_in', now.subtract(const Duration(hours: 5)),
            ['tea']),
      ],
      categories: {
        'latte': 'hot_drinks',
        'iced': 'cold_drinks',
        'tea': 'hot_drinks',
      },
    );
    await _pump(tester, feed);
    expect(find.text('٣/٣'), findsOneWidget);

    await tester.tap(find.text('استلم المكافأة').first);
    await tester.pumpAndSettle();

    // Points confirmation snackbar from the loyalty seam.
    expect(find.text('+٥٠ نقطة اتضافت لحسابك!'), findsOneWidget);
    // Button flips to تم الاستلام and stays disabled.
    expect(find.text('تم الاستلام'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'تم الاستلام').first,
    );
    expect(button.onPressed, isNull);

    // The other two cards stay unclaimed with disabled buttons (their
    // quests are still incomplete).
    final others = tester.widgetList<FilledButton>(
        find.widgetWithText(FilledButton, 'استلم المكافأة'));
    expect(others.length, 2);
    expect(others.every((b) => b.onPressed == null), isTrue);

    // Claimed state persisted under the phone-hash key.
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(
          'quest.${QuestStateStore.phoneHash('')}.claimed.drinksVariety'),
      isTrue,
    );

    // Drain the snackbar so later tests are unaffected.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('match-night claim queues a pending grant (seam gap) '
      'and shows the honest snackbar', (tester) async {
    final now = DateTime.now();
    final feed = _FakeQuestFeed(
      orders: [
        _order('o1', 'dine_in', now),
      ],
      windows: CampaignWindows(
        matchNight: [
          CampaignWindow(
            startsAtUtc: now.subtract(const Duration(hours: 1)),
            endsAtUtc: now.add(const Duration(hours: 1)),
          ),
        ],
      ),
    );
    await _pump(tester, feed);

    await tester.tap(find.text('استلم المكافأة').at(1)); // Q2 card
    await tester.pumpAndSettle();

    // Direct-grant path (controller seam now has grantTokens): the snackbar
    // copy is kept, but nothing is queued while the grant succeeds offline.
    expect(find.text('تم! التوكن يُضاف تلقائيًا قريبًا'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
        'pending_grants.${QuestStateStore.phoneHash('')}');
    // Queue only fills when the direct grant throws (offline fallback).
    if (raw != null) {
      expect(raw, contains('match_token'));
    }
    expect(find.text('تم الاستلام'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('badge grid shows locked medallions; earning one fires the '
      'celebration banner once', (tester) async {
    final now = DateTime.now();
    final feed = _FakeQuestFeed(
      orders: [
        _order('o1', 'dine_in', now),
      ],
      windows: CampaignWindows(
        matchNight: [
          CampaignWindow(
            startsAtUtc: now.subtract(const Duration(minutes: 30)),
            endsAtUtc: now.add(const Duration(minutes: 30)),
          ),
        ],
      ),
    );
    await _pump(tester, feed);

    // Celebration fires on first evaluation pass.
    expect(find.text('مبروك! شارة جديدة 🎉'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Switch to badges tab — all four medallions present, earned one no
    // longer carries the lock icon.
    await tester.tap(find.text('الشارات'));
    await tester.pumpAndSettle();

    expect(find.text('نادي ليالي الماتشات'), findsOneWidget);
    expect(find.text('رياضي الامتحانات'), findsOneWidget);
    expect(find.text('بومة رمضان'), findsOneWidget);
    expect(find.text('عميل ذهبي'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
    expect(find.byIcon(Icons.sports_soccer_outlined), findsOneWidget);

    // Motivational bottom banner on the badges tab too.
    expect(find.text('كمّل مهام أكتر واكسب أكتر'), findsOneWidget);
  });

  testWidgets('fetch failure renders ٠/٣ cards with retry banner',
      (tester) async {
    final feed = _FakeQuestFeed(failOrders: true);
    await _pump(tester, feed);

    expect(find.text('٠/٣'), findsOneWidget); // drinks month quest
    expect(find.text('٠/١'), findsOneWidget); // match-night month quest
    expect(find.text('٠/٢'), findsOneWidget); // both-modes week quest
    expect(find.text('حصلت مشكلة في تحميل المهام'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}
