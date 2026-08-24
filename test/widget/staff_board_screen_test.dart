// Widget tests for the staff board (#012): cards render live from a faked
// realtime stream with per-tab counts, قبول records the transition through
// the fake repo, رفض opens the reason sheet then cancels with it, the
// profiles.role probe failure renders the full-screen lock panel (retry
// recovers), realtime inserts fire the طلب جديد snackbar, and the check-in
// sheet records a walk-in visit. No network, no Supabase.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/l10n/strings_staff.dart';
import 'package:kady_app/data/repos/staff_orders_repository.dart';
import 'package:kady_app/domain/order_status_flow.dart';
import 'package:kady_app/ui/staff/staff_board_screen.dart';
import 'package:kady_app/ui/staff/widgets/order_card.dart';

class _FakeStaffOrdersRepo implements StaffOrdersRepo {
  final controller = StreamController<List<StaffOrder>>.broadcast();
  final transitions = <_RecordedTransition>[];
  final visits = <CheckInInput>[];

  VisitRecorded visitResult = const VisitRecorded(loyaltyPending: false);
  Object? accessError;

  void emit(List<StaffOrder> orders) => controller.add(orders);

  @override
  Stream<List<StaffOrder>> streamAll() => controller.stream;

  @override
  Future<Map<String, String>> fetchCustomerNames() async =>
      {'+201001234567': 'مصطفى'};

  @override
  Future<String?> fetchAddressText(String addressId) async =>
      'القاهرة الجديدة، شارع التسعين، التجمع الخامس';

  @override
  Future<Map<String, String>> fetchAddressMap(Set<String> ids) async =>
      {for (final id in ids) id: 'القاهرة الجديدة، شارع التسعين، التجمع الخامس'};

  @override
  Future<void> ensureStaffAccess() async {
    final error = accessError;
    if (error != null) throw error;
  }

  @override
  Future<void> transition(
    String orderId,
    OrderWireStatus toStatus, {
    String? rejectReason,
  }) async {
    transitions.add(_RecordedTransition(orderId, toStatus, rejectReason));
  }

  @override
  Future<VisitRecorded> registerVisit(CheckInInput input) async {
    visits.add(input);
    return visitResult;
  }
}

class _RecordedTransition {
  const _RecordedTransition(this.orderId, this.to, this.reason);

  final String orderId;
  final OrderWireStatus to;
  final String? reason;
}

StaffOrder _order({
  String id = 'o1',
  int number = 1001,
  String modeWire = 'dine_in',
  OrderWireStatus status = OrderWireStatus.received,
  Duration createdAgo = const Duration(minutes: 5),
  String? phone = '+201001234567',
  String? addressId,
}) {
  return StaffOrder(
    id: id,
    displayNumber: number,
    phone: phone,
    modeWire: modeWire,
    status: status,
    lines: const [
      OrderItemLine(name: 'لاتيه', qty: 2),
      OrderItemLine(name: 'كرواسون', qty: 1),
    ],
    totalEgp: 95,
    tableArea: modeWire == 'dine_in' ? 'طاولة 12' : null,
    pickupSlotUtc: modeWire == 'pickup'
        ? DateTime.utc(2026, 8, 22, 10, 30)
        : null,
    addressId: addressId,
    createdAtUtc: DateTime.now().toUtc().subtract(createdAgo),
  );
}

Future<_FakeStaffOrdersRepo> _pumpBoard(
  WidgetTester tester, [
  _FakeStaffOrdersRepo? injected,
]) async {
  final repo = injected ?? _FakeStaffOrdersRepo();
  await tester.pumpWidget(
    // Riverpod 3 auto-retries failing providers (backoff up to ~40s), which
    // would keep the board stuck on the spinner instead of surfacing the
    // lock panel. Tests assert the immediate error UI, so retries are off.
    ProviderScope(
      overrides: [staffOrdersRepoProvider.overrideWithValue(repo)],
      retry: (_, _) => null,
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StaffBoardScreen(),
        ),
      ),
    ),
  );
  await tester.pump(); // access probe resolves
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return repo;
}

Future<void> _pumpCard(WidgetTester tester, StaffOrder order) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ListView(
            children: [
              OrderCard(
                order: order,
                strings: StaffStrings.of(AppLang.ar),
                lang: AppLang.ar,
                nowUtc: DateTime.now().toUtc(),
                onTransition: (_, {String? rejectReason}) async {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('board renders live cards from the stream with per-tab counts',
      (tester) async {
    // Tall surface so the lazily-built ListView materializes all four cards.
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _pumpBoard(tester);

    repo.emit([
      _order(id: 'o1', number: 1001, status: OrderWireStatus.inPrep),
      _order(id: 'o2', number: 1002, status: OrderWireStatus.received),
      _order(
          id: 'o3',
          number: 1003,
          modeWire: 'pickup',
          status: OrderWireStatus.received),
      _order(
          id: 'o4',
          number: 1004,
          modeWire: 'delivery',
          status: OrderWireStatus.received,
          addressId: 'addr1'),
    ]);
    await tester.pump();

    expect(find.text('#1001'), findsOneWidget);
    expect(find.text('#1004'), findsOneWidget);
    expect(find.text('الكل (4)'), findsOneWidget);
    expect(find.text('صالة (2)'), findsOneWidget);
    expect(find.text('استلام (1)'), findsOneWidget);
    expect(find.text('توصيل (1)'), findsOneWidget);

    // Rolling prep mean: only o1 is in_prep at ~5 minutes → 5 دقايق.
    expect(find.textContaining('متوسط وقت التحضير'), findsOneWidget);

    // Customer name resolved from the cached customers map; dine-in timing
    // shows the table tag (o1 + o2); delivery shows the short address part.
    expect(find.text('مصطفى'), findsWidgets);
    expect(find.text('طاولة 12'), findsNWidgets(2));

    // The address lookup is an async family provider — one more frame and
    // the delivery timing line shows the short Cairo address.
    await tester.pump();
    expect(find.textContaining('القاهرة الجديدة'), findsOneWidget);

    // Items summary + total ride along (suffix ج.م per checkout strings).
    expect(find.text('لاتيه ×2 · كرواسون'), findsNWidgets(4));
    expect(find.text('95 ج.م'), findsNWidgets(4));
  });

  testWidgets('tapping قبول calls the repo transition to accepted',
      (tester) async {
    final repo = await _pumpBoard(tester);
    repo.emit([
      _order(id: 'o4', number: 1004, modeWire: 'delivery'),
    ]);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'قبول').first);
    await tester.pump();

    expect(repo.transitions, hasLength(1));
    expect(repo.transitions.single.orderId, 'o4');
    expect(repo.transitions.single.to, OrderWireStatus.accepted);
  });

  testWidgets('reject flow opens the reason sheet then cancels with it',
      (tester) async {
    final repo = await _pumpBoard(tester);
    repo.emit([_order(id: 'o1', number: 1001)]);
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'رفض').first);
    await tester.pump(); // route pushed
    await tester
        .pump(const Duration(milliseconds: 350)); // entrance animation done
    expect(find.text('سبب الرفض'), findsOneWidget);

    // Confirm stays disabled while blank.
    expect(
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'تأكيد الرفض'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'المكونات نفدت');
    await tester.pump();
    await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'تأكيد الرفض'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'تأكيد الرفض'));
    await tester.pump();

    expect(repo.transitions.single.orderId, 'o1');
    expect(repo.transitions.single.to, OrderWireStatus.cancelled);
    expect(repo.transitions.single.reason, 'المكونات نفدت');
  });

  testWidgets('probe failure renders the lock panel and retry recovers',
      (tester) async {
    final repo = _FakeStaffOrdersRepo()..accessError =
        const StaffPermissionException();
    await _pumpBoard(tester, repo);

    expect(find.text('قفل 🔒 بلا صلاحية موظف'), findsOneWidget);
    expect(
      find.text('شغّل SQL ترقية الحساب من docs/SUPABASE_SETUP.md'),
      findsOneWidget,
    );

    repo.accessError = null; // owner elevated via SQL in the meantime
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pump(); // loading
    await tester.pump(); // data

    expect(find.text('قفل 🔒 بلا صلاحية موظف'), findsNothing);
    expect(find.textContaining('متوسط وقت التحضير'), findsOneWidget);
  });

  testWidgets('realtime insert fires the new-order snackbar once',
      (tester) async {
    final repo = await _pumpBoard(tester);

    repo.emit([_order(id: 'o1', number: 1001)]);
    await tester.pump();

    repo.emit([
      _order(id: 'o1', number: 1001),
      _order(id: 'o9', number: 1050),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('طلب جديد #1050 🛎️'), findsOneWidget);

    // A re-emission without new ids must not re-fire the banner.
    repo.emit([
      _order(id: 'o1', number: 1001),
      _order(id: 'o9', number: 1050),
    ]);
    await tester.pump();
    expect(find.text('طلب جديد #1050 🛎️'), findsOneWidget);
  });

  testWidgets('action set follows status × mode', (tester) async {
    await _pumpCard(
      tester,
      _order(status: OrderWireStatus.accepted),
    );
    expect(find.text('ابدأ التحضير'), findsOneWidget);

    await _pumpCard(tester, _order(status: OrderWireStatus.inPrep));
    expect(find.text('جاهز'), findsOneWidget);

    await _pumpCard(
      tester,
      _order(modeWire: 'dine_in', status: OrderWireStatus.ready),
    );
    expect(find.text('تم التسليم'), findsOneWidget);

    await _pumpCard(
      tester,
      _order(
          id: 'o6',
          number: 1006,
          modeWire: 'delivery',
          status: OrderWireStatus.ready),
    );
    expect(find.text('تسليم للسائق'), findsOneWidget);

    await _pumpCard(
      tester,
      _order(
          id: 'o7',
          number: 1007,
          modeWire: 'delivery',
          status: OrderWireStatus.outForDelivery),
    );
    expect(find.text('تم التوصيل'), findsOneWidget);

    // Terminal states carry no actions.
    await _pumpCard(
      tester,
      _order(status: OrderWireStatus.done),
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('check-in sheet records a walk-in visit and snacks success',
      (tester) async {
    final repo = await _pumpBoard(tester);
    repo.emit([_order(id: 'o1')]);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.how_to_reg_outlined));
    await tester.pump(); // route pushed
    await tester
        .pump(const Duration(milliseconds: 350)); // entrance animation done
    expect(find.text('تسجيل زيارة داخل الكافيه'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '+201001234567');
    await tester.enterText(find.byType(TextField).at(1), '60');
    await tester.tap(find.text('داخل'));
    await tester.enterText(find.byType(TextField).at(2), '12');
    await tester.pump();

    await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'تسجيل الزيارة'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الزيارة'));
    await tester.pump(); // submit resolves
    await tester.pump(); // sheet pops
    await tester.pump(const Duration(milliseconds: 400)); // snackbar in

    expect(repo.visits, hasLength(1));
    expect(repo.visits.single.phone, '+201001234567');
    expect(repo.visits.single.spendEgp, 60);
    expect(repo.visits.single.tableArea, 'داخل - طاولة 12');

    // Stamp written directly → plain success copy (not the pending one).
    expect(find.text('الزيارة اتسجلت ✅'), findsOneWidget);
    expect(find.textContaining('الختم يتضاف'), findsNothing);
  });
}
