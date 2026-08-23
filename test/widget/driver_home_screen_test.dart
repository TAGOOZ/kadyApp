// Widget tests for the driver shell (#014): both tabs render from fakes
// (cards with pickup line / cash highlight / items chip; history rows under
// the Cairo-day summary header), the detail route advances the three-step
// stepper recording every call through the repo (accept → picked up →
// delivered, sticky button disabled at the end), directions copy the Google
// Maps URL for an Arabic address, empty states, the realtime توصيلة جديدة
// snackbar and the permission lock panel with retry recovery. No network,
// no Supabase.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/data/repos/driver_orders_repository.dart';
import 'package:kady_app/data/repos/orders_repository.dart' show cairoUtcOffset;
import 'package:kady_app/domain/order_status_flow.dart';
import 'package:kady_app/ui/driver/driver_home_screen.dart';
import 'package:kady_app/ui/driver/widgets/delivery_progress_bar.dart';

class _FakeDriverOrdersRepo implements DriverOrdersRepo {
  final controller = StreamController<List<DriverOrder>>.broadcast();
  final accepts = <String>[];
  final pickedUps = <String>[];
  final delivered = <String>[];

  List<DriverOrder> historySeed = const [];
  Object? accessError;

  void emit(List<DriverOrder> orders) => controller.add(orders);

  @override
  Stream<List<DriverOrder>> streamAssigned() => controller.stream;

  @override
  Future<void> accept(String orderId) async => accepts.add(orderId);

  @override
  Future<void> markPickedUp(String orderId) async => pickedUps.add(orderId);

  @override
  Future<void> markDelivered(String orderId) async => delivered.add(orderId);

  @override
  Future<List<DriverOrder>> fetchHistory() async => historySeed;

  @override
  Future<String?> fetchAddressText(String addressId) async =>
      'القاهرة الجديدة، شارع التسعين، التجمع الخامس';

  @override
  Future<List<String>> fetchEventStatuses(String orderId) async => const [];

  @override
  Future<Map<String, String>> fetchCustomerNames() async => {
    '+201001234567': 'مصطفى',
  };

  @override
  Future<void> ensureDriverAccess() async {
    final error = accessError;
    if (error != null) throw error;
  }
}

DriverOrder _order({
  String id = 'o1',
  int number = 1001,
  OrderWireStatus status = OrderWireStatus.outForDelivery,
  Duration createdAgo = const Duration(minutes: 5),
}) {
  return DriverOrder(
    id: id,
    displayNumber: number,
    phone: '+201001234567',
    status: status,
    lines: const [
      DriverItemLine(name: 'لاتيه', qty: 1),
      DriverItemLine(name: 'كرواسون', qty: 1),
    ],
    totalEgp: 90,
    notes: '[REDEEMED:free_drink:200] برج 5، الدور الثالث',
    addressId: 'addr-1',
    createdAtUtc: DateTime.now().toUtc().subtract(createdAgo),
  );
}

/// The shared items line type lives behind the repo typedef.
typedef DriverItemLine = OrderItemLine;

Future<_FakeDriverOrdersRepo> _pumpHome(
  WidgetTester tester, [
  _FakeDriverOrdersRepo? injected,
]) async {
  final repo = injected ?? _FakeDriverOrdersRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [driverOrdersRepoProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: DriverHomeScreen(),
        ),
      ),
    ),
  );
  await tester.pump(); // access probe resolves
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return repo;
}

void main() {
  testWidgets('طلباتي tab renders live cards with cash highlight and chips', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _pumpHome(tester);

    repo.emit([_order(id: 'o1', number: 1023)]);
    await tester.pump();
    await tester.pump(); // address family provider resolves

    expect(find.text('#1023'), findsOneWidget);
    expect(find.text('طلباتي'), findsOneWidget);
    expect(find.text('السجل'), findsOneWidget);
    expect(find.text('الاستلام من كافيه القاضي ☕'), findsOneWidget);
    // Address one-liner = first comma-part of the resolved address.
    expect(find.text('القاهرة الجديدة'), findsOneWidget);
    // Cash highlight orange bold: X ج.م كاش.
    expect(find.text('90 ج.م كاش'), findsOneWidget);
    // Items count chip.
    expect(find.text('2 أصناف'), findsOneWidget);
    // Identity stub rides in the app bar.
    expect(find.text('كريم م.'), findsOneWidget);
  });

  testWidgets('empty assigned feed shows مفيش توصيلات حالياً', (tester) async {
    final repo = await _pumpHome(tester);

    repo.emit(const []);
    await tester.pump();

    expect(find.text('مفيش توصيلات حالياً'), findsOneWidget);
  });

  testWidgets('detail advances the stepper through the repo, then locks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _pumpHome(tester);

    repo.emit([_order(id: 'o9', number: 1009)]);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('#1009'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route animation

    // Detail content: stripped notes, full address, items, customer block.
    expect(find.textContaining('برج 5، الدور الثالث'), findsOneWidget);
    expect(find.textContaining('[REDEEMED'), findsNothing);
    expect(
      find.text('القاهرة الجديدة، شارع التسعين، التجمع الخامس'),
      findsOneWidget,
    );
    expect(find.text('مصطفى'), findsOneWidget);
    expect(find.byType(DeliveryProgressBar), findsOneWidget);

    // Step 1 → قبول التوصيلة.
    await tester.tap(find.widgetWithText(FilledButton, 'قبول التوصيلة'));
    await tester.pump();
    expect(repo.accepts.single, 'o9');
    expect(repo.pickedUps, isEmpty);

    // Step 2 → استلمت من الكافيه.
    await tester.tap(find.widgetWithText(FilledButton, 'استلمت من الكافيه'));
    await tester.pump();
    expect(repo.pickedUps.single, 'o9');
    expect(repo.delivered, isEmpty);

    // Step 3 → تم التوصيل (status done write-through).
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'تم التوصيل').last,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'تم التوصيل').last);
    await tester.pump();

    expect(repo.delivered.single, 'o9');

    // Terminal: button flips to the done label and disables.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'تم التوصيل ✅'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('phone row tap snacks الاتصال قريبًا (MVP)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _pumpHome(tester);

    repo.emit([_order()]);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('#1001'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('+201001234567'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('الاتصال قريبًا'), findsOneWidget);
  });

  testWidgets('فتح الاتجاهات copies the encoded Maps URL and snacks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (message) async {
        if (message.method == 'Clipboard.setData') {
          copied = (message.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final repo = await _pumpHome(tester);
    repo.emit([_order()]);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('#1001'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('فتح الاتجاهات'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('تم نسخ الرابط'), findsOneWidget);
    expect(
      copied,
      startsWith('https://www.google.com/maps/search/?api=1&query='),
    );
    expect(copied, isNot(contains(' '))); // Arabic spaces percent-encoded
    expect(
      Uri.decodeComponent(copied!.split('query=').last),
      'القاهرة الجديدة، شارع التسعين، التجمع الخامس',
    );
  });

  testWidgets('السجل tab lists history under the Cairo-day cash summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _FakeDriverOrdersRepo();
    final nowUtc = DateTime.now().toUtc();
    // Deterministic same-Cairo-day instants: noon today on the Cairo wall
    // clock is never near midnight (ADR-0009).
    final offset = cairoUtcOffset(nowUtc);
    final cairoNow = nowUtc.add(offset);
    final cairoNoonUtc = DateTime.utc(
      cairoNow.year,
      cairoNow.month,
      cairoNow.day,
      12,
    ).subtract(offset);

    repo.historySeed = [
      // Today on the Cairo clock ✓
      DriverOrder(
        id: 'h1',
        displayNumber: 1001,
        status: OrderWireStatus.done,
        lines: const [],
        totalEgp: 90,
        addressId: 'addr-1',
        createdAtUtc: cairoNoonUtc,
      ),
      DriverOrder(
        id: 'h2',
        displayNumber: 1002,
        status: OrderWireStatus.done,
        lines: const [],
        totalEgp: 60,
        addressId: 'addr-1',
        createdAtUtc: cairoNoonUtc.subtract(const Duration(hours: 3)),
      ),
      // ~a day ago → outside today ✗
      DriverOrder(
        id: 'h3',
        displayNumber: 999,
        status: OrderWireStatus.done,
        lines: const [],
        totalEgp: 500,
        addressId: 'addr-1',
        createdAtUtc: cairoNoonUtc.subtract(const Duration(hours: 30)),
      ),
    ];

    await _pumpHome(tester, repo);
    await tester.tap(find.text('السجل'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('توصيلات اليوم 2 · محصّل 150 ج.م'), findsOneWidget);
    expect(find.text('#1001'), findsOneWidget);
    expect(find.text('#1002'), findsOneWidget);
    expect(find.text('#999'), findsOneWidget);
    // Cash per row without the كاش suffix.
    expect(find.text('90 ج.م'), findsOneWidget);
  });

  testWidgets('realtime insert fires the توصيلة جديدة snackbar once', (
    tester,
  ) async {
    final repo = await _pumpHome(tester);

    repo.emit([_order(id: 'o1', number: 1001)]);
    await tester.pump();

    repo.emit([_order(id: 'o1', number: 1001), _order(id: 'o8', number: 1050)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('توصيلة جديدة 🛵'), findsOneWidget);

    // Re-emission without new ids must not re-fire.
    repo.emit([_order(id: 'o1', number: 1001), _order(id: 'o8', number: 1050)]);
    await tester.pump();
    expect(find.text('توصيلة جديدة 🛵'), findsOneWidget);
  });

  testWidgets('probe failure renders the lock panel and retry recovers', (
    tester,
  ) async {
    final repo = _FakeDriverOrdersRepo()
      ..accessError = const DriverPermissionException();
    await _pumpHome(tester, repo);

    expect(find.text('قفل 🔒 بلا صلاحية سائق'), findsOneWidget);
    expect(
      find.text('شغّل SQL ترقية الحساب من docs/SUPABASE_SETUP.md'),
      findsOneWidget,
    );

    repo.accessError = null; // owner elevated via SQL in the meantime
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump(); // loading
    await tester.pump(); // data

    expect(find.text('قفل 🔒 بلا صلاحية سائق'), findsNothing);
    expect(find.text('طلباتي'), findsOneWidget);
  });
}
