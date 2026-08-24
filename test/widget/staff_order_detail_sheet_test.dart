// RED: StaffOrderDetailSheet bottom sheet (FEATURES §6, G10b P2)
// Reuses OrderCard expanded state — shows customer phone, items, mode,
// status chip and an advance button; tapping advance delegates to
// staffOrdersRepo.transition. This test MUST fail before the sheet exists
// (TDD red phase — import resolves only after GREEN creates the widget).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kady_app/data/repos/staff_orders_repository.dart';
import 'package:kady_app/domain/order_status_flow.dart';
import 'package:kady_app/ui/staff/widgets/staff_order_detail_sheet.dart';

class _FakeStaffOrdersRepo implements StaffOrdersRepo {
  final transitions = <_RecordedTransition>[];

  @override
  Stream<List<StaffOrder>> streamAll() => const Stream.empty();

  @override
  Future<Map<String, String>> fetchCustomerNames() async => const {};

  @override
  Future<String?> fetchAddressText(String addressId) async => null;

  @override
  Future<void> ensureStaffAccess() async {}

  @override
  Future<void> transition(
    String orderId,
    OrderWireStatus toStatus, {
    String? rejectReason,
  }) async {
    transitions.add(_RecordedTransition(orderId, toStatus, rejectReason));
  }

  @override
  Future<VisitRecorded> registerVisit(CheckInInput input) async =>
      const VisitRecorded(loyaltyPending: false);
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
  String? phone = '+201001234567',
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
    createdAtUtc: DateTime.utc(2026, 8, 22, 12),
  );
}

Future<void> _pumpSheet(
  WidgetTester tester,
  StaffOrder order, {
  String? customerName,
  String? addressText,
  _FakeStaffOrdersRepo? repo,
}) async {
  SharedPreferences.setMockInitialValues({});
  final fake = repo ?? _FakeStaffOrdersRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [staffOrdersRepoProvider.overrideWithValue(fake)],
      retry: (_, _) => null,
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StaffOrderDetailSheet(
              order: order,
              customerName: customerName,
              addressText: addressText,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
      'shows customer phone, items, mode, status chip and advance button',
      (tester) async {
    await _pumpSheet(
      tester,
      _order(),
      customerName: 'مصطفى',
    );

    // Customer phone (canonical Customer key §11.3) — sheet must surface it.
    expect(find.textContaining('+201001234567'), findsOneWidget);

    // Items — detailed lines (not just the collapsed summary).
    expect(find.textContaining('لاتيه'), findsOneWidget);
    expect(find.textContaining('كرواسون'), findsOneWidget);

    // Mode badge — dine_in → صالة (reuses checkout strings parity with card).
    expect(find.text('صالة'), findsOneWidget);

    // Status chip — received → جديد.
    expect(find.text('جديد'), findsOneWidget);

    // Advance button — received → قبول (via staffOrdersRepo).
    expect(find.widgetWithText(FilledButton, 'قبول'), findsOneWidget);
  });

  testWidgets('tapping advance calls staffOrdersRepo.transition', (tester) async {
    final repo = _FakeStaffOrdersRepo();
    await _pumpSheet(
      tester,
      _order(id: 'o9', number: 1009),
      repo: repo,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'قبول'));
    await tester.pump();

    expect(repo.transitions, hasLength(1));
    expect(repo.transitions.single.orderId, 'o9');
    expect(repo.transitions.single.to, OrderWireStatus.accepted);
  });

  testWidgets('shows total and handles pickup mode label', (tester) async {
    await _pumpSheet(
      tester,
      _order(modeWire: 'pickup', status: OrderWireStatus.accepted),
    );

    expect(find.text('استلام'), findsOneWidget);
    expect(find.textContaining('95'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'ابدأ التحضير'), findsOneWidget);
  });
}
