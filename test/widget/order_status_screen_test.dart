// Widget tests for the order status screen (#006): a fake repository
// stream emits the staff-driven progression new → in_prep → ready and the
// timeline's current index must follow across pumps (ADR-0006 realtime —
// no auto-advance timer). Delivery shows the driver card at
// في الطريق إليك; cancelled renders the red terminal row; stream errors
// map to the retry banner. No network, no Supabase.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/launcher/app_launcher.dart';
import 'package:kady_app/core/riverpod_retry.dart';
import 'package:kady_app/data/repos/order_status_repository.dart';
import 'package:kady_app/domain/order_status_flow.dart';
import 'package:kady_app/ui/orders/order_status_screen.dart';
import 'package:kady_app/ui/orders/widgets/driver_card.dart';
import 'package:kady_app/ui/orders/widgets/status_timeline.dart';
import 'package:url_launcher/url_launcher.dart';

class _FakeFallbackLauncher implements AppLauncher {
  @override
  Future<bool> canLaunchUrl(Uri uri) async => false;

  @override
  Future<bool> launchUrl(Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async => false;

  @override
  Future<void> copy(String text) async {}
}

CustomerOrder _order({
  required String modeWire,
  required OrderWireStatus status,
  bool hasDriver = false,
  String? rejectReason,
}) {
  return CustomerOrder(
    id: 'o1',
    displayNumber: 1023,
    modeWire: modeWire,
    status: status,
    createdAtUtc: DateTime.utc(2026, 8, 22, 9),
    itemCount: 2,
    totalEgp: 95,
    hasDriver: hasDriver,
    rejectReason: rejectReason,
  );
}

class _FakeOrderStatusRepo implements OrderStatusRepo {
  final _orderController = StreamController<CustomerOrder?>.broadcast();

  void emit(CustomerOrder order) => _orderController.add(order);

  @override
  Stream<CustomerOrder?> watchOrder(String orderId) => _orderController.stream;

  @override
  Stream<List<CustomerOrder>> watchOwnOrders(String googleUserId) =>
      const Stream.empty();

  @override
  Future<List<CustomerOrder>> fetchOwnOrders(String googleUserId) async =>
      const [];

  @override
  Future<List<OrderEventRow>> fetchEvents(String orderId) async => const [];
}

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this._lang);

  final AppLang _lang;

  @override
  AppLang build() => _lang;
}

Future<void> _pump(
  WidgetTester tester,
  OrderStatusRepo repo, {
  AppLang lang = AppLang.ar,
  AppLauncher? launcher,
}) async {
  final fakeLauncher = launcher ?? _FakeFallbackLauncher();
  await tester.pumpWidget(
    ProviderScope(retry: noAutoRetry,
      overrides: [
        orderStatusRepoProvider.overrideWithValue(repo),
        localeNotifierProvider.overrideWith(() => _FixedLocale(lang)),
        appLauncherProvider.overrideWithValue(fakeLauncher),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: OrderStatusScreen(orderId: 'o1'),
        ),
      ),
    ),
  );
  await tester.pump(); // resolve initial loading state
}

void main() {
  testWidgets('timeline follows realtime progression new → in_prep → ready',
      (tester) async {
    final repo = _FakeOrderStatusRepo();
    await _pump(tester, repo);

    int currentIndex() =>
        tester.widget<StatusTimeline>(find.byType(StatusTimeline)).currentIndex;

    repo.emit(_order(modeWire: 'dine_in', status: OrderWireStatus.received));
    await tester.pump();
    expect(currentIndex(), 0);

    repo.emit(_order(modeWire: 'dine_in', status: OrderWireStatus.inPrep));
    await tester.pump();
    expect(currentIndex(), 2);

    repo.emit(_order(modeWire: 'dine_in', status: OrderWireStatus.ready));
    await tester.pump();
    expect(currentIndex(), 3);

    // All five dine-in steps render with their Arabic labels.
    expect(find.text('تم الاستلام'), findsOneWidget);
    expect(find.text('قيد التحضير'), findsOneWidget);
    expect(find.text('جاهز'), findsOneWidget);
    expect(find.byIcon(Icons.room_service_outlined), findsOneWidget);
  });

  testWidgets('delivery driver card appears only at في الطريق إليك',
      (tester) async {
    final repo = _FakeOrderStatusRepo();
    await _pump(tester, repo);

    repo.emit(_order(
      modeWire: 'delivery',
      status: OrderWireStatus.inPrep,
      hasDriver: true,
    ));
    await tester.pump();
    expect(find.byType(DriverCard), findsNothing);

    // Driver extras gate on both the step AND an assigned driver.
    repo.emit(_order(
      modeWire: 'delivery',
      status: OrderWireStatus.outForDelivery,
      hasDriver: true,
    ));
    await tester.pump();
    expect(find.byType(DriverCard), findsOneWidget);
    expect(find.text('كريم م.'), findsOneWidget);
    expect(find.byIcon(Icons.moped_outlined), findsOneWidget);

    // Phone row tap → MVP snackbar (no tel: launch).
    await tester.tap(find.byIcon(Icons.phone_outlined));
    await tester.pump();
    expect(find.text('الاتصال قريبًا'), findsOneWidget);

    // Run the snack through entrance → 4s duration → exit so the next
    // snackbar isn't queued behind it.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Directions tap → snackbar too.
    await tester.ensureVisible(find.text('فتح الاتجاهات'));
    await tester.pump();
    await tester.tap(find.text('فتح الاتجاهات'));
    await tester.pump();
    expect(find.text('الاتجاهات المباشرة قريبًا'), findsOneWidget);

    // Without an assigned driver there is no card.
    repo.emit(_order(
      modeWire: 'delivery',
      status: OrderWireStatus.outForDelivery,
      hasDriver: false,
    ));
    await tester.pump();
    expect(find.byType(DriverCard), findsNothing);
  });

  testWidgets('reaching done fires the celebration banner once',
      (tester) async {
    final repo = _FakeOrderStatusRepo();
    await _pump(tester, repo);

    repo.emit(_order(
      modeWire: 'dine_in',
      status: OrderWireStatus.done,
    ));
    await tester.pump();
    // Banner + snackbar share the copy; confetti painter is active.
    expect(find.text('تم التقديم 🎉'), findsWidgets);

    // A duplicate `done` emission must not re-trigger anything odd.
    repo.emit(_order(
      modeWire: 'dine_in',
      status: OrderWireStatus.done,
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled renders the red terminal row with reason',
      (tester) async {
    final repo = _FakeOrderStatusRepo();
    await _pump(tester, repo);

    repo.emit(_order(
      modeWire: 'pickup',
      status: OrderWireStatus.cancelled,
      rejectReason: 'المكونات نفدت',
    ));
    await tester.pump();

    expect(find.text('مُلغي'), findsOneWidget);
    expect(find.text('سبب الإلغاء: المكونات نفدت'), findsOneWidget);
    final timeline =
        tester.widget<StatusTimeline>(find.byType(StatusTimeline));
    expect(timeline.cancelled, isTrue);
    expect(timeline.currentIndex, -1);
  });

  testWidgets('stream errors map to the retry banner', (tester) async {
    final repo = _FakeOrderStatusRepo();
    await _pump(tester, repo);

    repo._orderController.addError(Exception('realtime down'));
    repo._orderController.close();
    await tester.pump();

    expect(find.text('حصلت مشكلة في تحميل الطلبات'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('english locale renders english timeline labels and driver copy',
      (tester) async {
    final repo = _FakeOrderStatusRepo();
    await _pump(tester, repo, lang: AppLang.en);

    expect(find.text('Track order'), findsOneWidget);

    repo.emit(_order(modeWire: 'dine_in', status: OrderWireStatus.inPrep));
    await tester.pump();
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('In preparation'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);

    // Driver card copy comes from the EN catalog entries.
    repo.emit(_order(
      modeWire: 'delivery',
      status: OrderWireStatus.outForDelivery,
      hasDriver: true,
    ));
    await tester.pump();
    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('Karim M.'), findsOneWidget);
    expect(find.text('Out for delivery'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.phone_outlined));
    await tester.pump();
    expect(find.text('Calling is coming soon'), findsOneWidget);

    // Run the snack through entrance → duration → exit.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('Open directions'));
    await tester.pump();
    await tester.tap(find.text('Open directions'));
    await tester.pump();
    expect(find.text('Live directions coming soon'), findsOneWidget);
  });

  testWidgets('arabic locale keeps arabic timeline labels and driver copy',
      (tester) async {
    final repo = _FakeOrderStatusRepo();
    await _pump(tester, repo, lang: AppLang.ar);

    repo.emit(_order(
      modeWire: 'delivery',
      status: OrderWireStatus.outForDelivery,
      hasDriver: true,
    ));
    await tester.pump();

    expect(find.text('في الطريق إليك'), findsOneWidget);
    expect(find.text('السائق'), findsOneWidget);
    expect(find.text('كريم م.'), findsOneWidget);
  });

  testWidgets('english delivered banner uses the english done-step label',
      (tester) async {
    final repo = _FakeOrderStatusRepo();
    await _pump(tester, repo, lang: AppLang.en);

    repo.emit(_order(
      modeWire: 'dine_in',
      status: OrderWireStatus.done,
    ));
    await tester.pump();

    expect(find.text('Served 🎉'), findsWidgets);
  });
}
