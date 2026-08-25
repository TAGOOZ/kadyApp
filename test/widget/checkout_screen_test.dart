// Widget tests for checkout → confirmation (issue #003): totals render with
// no delivery-fee row for dine-in, submit is blocked without the mode field,
// guests are bounced to the save prompt (RLS), double-tap is throttled, and
// a successful placeOrder lands on /confirmation with the DB display number.
// All Supabase traffic goes through a fake OrdersRepo — no network.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/orders_repository.dart';
import 'package:kady_app/domain/auth_controller.dart';
import 'package:kady_app/domain/cart_controller.dart';
import 'package:kady_app/ui/cart/checkout_screen.dart';
import 'package:kady_app/ui/cart/order_confirmation_screen.dart';

const _tea = MenuItem(
  id: 'tea',
  slug: 'tea',
  nameAr: 'شاي',
  nameEn: 'Tea',
  descAr: '',
  descEn: '',
  priceEgp: 40,
  isAvailable: true,
  categorySlug: 'hot',
);

const _biscuit = MenuItem(
  id: 'biscuit',
  slug: 'biscuit',
  nameAr: 'بسكويت',
  nameEn: 'Biscuit',
  descAr: '',
  descEn: '',
  priceEgp: 15,
  isAvailable: true,
  categorySlug: 'snacks',
);

class _FakeOrdersRepo implements OrdersRepo {
  int placeOrderCalls = 0;
  NewOrder? lastOrder;
  Completer<void>? _gate;

  void holdNextSubmit() => _gate = Completer<void>();
  void releaseSubmit() {
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<int> fetchDeliveryFee() async => defaultDeliveryFeeEgp;

  @override
  Future<List<SavedAddress>> fetchAddresses(String googleUserId) async =>
      const [];

  @override
  Future<SavedAddress> saveAddress(SavedAddressInput input) async =>
      SavedAddress(id: 'addr-1', label: input.label, addressText: input.addressText);

  @override
  Future<PlacedOrder> placeOrder(NewOrder order) async {
    placeOrderCalls++;
    lastOrder = order;
    final gate = _gate;
    if (gate != null) await gate.future;
    return const PlacedOrder(id: 'order-1', displayNumber: 1023);
  }
}

class _FixedAuth extends AuthController {
  _FixedAuth(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

class _DineInDraft extends CheckoutDraftController {
  @override
  CheckoutDraft build() => const CheckoutDraft(mode: OrderMode.dineIn);
}

class _FailingOrdersRepo extends _FakeOrdersRepo {
  @override
  Future<PlacedOrder> placeOrder(NewOrder order) async {
    placeOrderCalls++;
    lastOrder = order;
    throw Exception('RLS denied');
  }
}

class _DeliveryFakeRepo extends _FakeOrdersRepo {
  @override
  Future<List<SavedAddress>> fetchAddresses(String googleUserId) async => [
        SavedAddress(id: 'addr-1', label: AddressLabel.home, addressText: 'شارع النيل ١٠'),
      ];
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/checkout',
    routes: [
      GoRoute(
        path: '/checkout',
        builder: (_, _) => const CheckoutScreen(),
      ),
      GoRoute(
        path: '/confirmation',
        builder: (_, _) => const OrderConfirmationScreen(),
      ),
    ],
  );
}

Future<void> _pumpWithDraft(
  WidgetTester tester, {
  required AuthState authState,
  required OrdersRepo repo,
  required CheckoutDraft Function() draftBuilder,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersRepoProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => _FixedAuth(authState)),
        checkoutDraftProvider.overrideWith(
          // ignore: avoid_types_on_closure_parameters
          () => _CustomDraft(draftBuilder),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: _router(),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    ),
  );
  final element = tester.element(find.byType(CheckoutScreen));
  final container = ProviderScope.containerOf(element);
  container.read(cartProvider.notifier).addItem(_tea, const ItemConfig(), qty: 2);
  container.read(cartProvider.notifier).addItem(_biscuit, const ItemConfig());
  await tester.pumpAndSettle();
}

class _CustomDraft extends CheckoutDraftController {
  _CustomDraft(this.builder);
  final CheckoutDraft Function() builder;
  @override
  CheckoutDraft build() => builder();
}

Future<void> _pump(
  WidgetTester tester, {
  required AuthState authState,
  required OrdersRepo repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersRepoProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => _FixedAuth(authState)),
        checkoutDraftProvider.overrideWith(_DineInDraft.new),
      ],
      child: MaterialApp.router(
        routerConfig: _router(),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    ),
  );

  // Seed the cart after the first frame: 40×2 + 15 = 95 EGP subtotal.
  final element = tester.element(find.byType(CheckoutScreen));
  final container = ProviderScope.containerOf(element);
  container.read(cartProvider.notifier).addItem(_tea, const ItemConfig(), qty: 2);
  container.read(cartProvider.notifier).addItem(_biscuit, const ItemConfig());

  await tester.pumpAndSettle();
}

const _ready = AuthState(
  phase: AuthPhase.ready,
  googleUser: GoogleProfile(id: 'g1'),
  phone: '+201000000000',
);

void main() {
  testWidgets('dine-in renders totals without fee row and real earn preview',
      (tester) async {
    final repo = _FakeOrdersRepo();
    await _pump(tester, authState: _ready, repo: repo);

    // Subtotal row + total row both read 95 ج.م; no delivery-fee row.
    expect(find.text('95 ج.م'), findsNWidgets(2));
    expect(find.text('رسوم التوصيل'), findsNothing);
    expect(find.text('الإجمالي'), findsOneWidget);
    // 95/10 = 9.5 → round half-up → 10 pts.
    expect(find.text('هذا الطلب يضيف ~10 نقطة لحسابك ☕'), findsOneWidget);
    // Fixed cash copy for صالة.
    expect(find.text('الدفع في الكافيه نقداً'), findsOneWidget);
  });

  testWidgets('submit blocked without table/area — form kept, no insert',
      (tester) async {
    final repo = _FakeOrdersRepo();
    await _pump(tester, authState: _ready, repo: repo);

    await tester.tap(find.text('تأكيد الطلب · 95 ج.م'));
    await tester.pumpAndSettle();

    expect(find.text('حدّد رقم الترابيزة أو المنطقة'), findsOneWidget);
    expect(repo.placeOrderCalls, 0);
    expect(find.text('تأكيد الطلب · 95 ج.م'), findsOneWidget);
  });

  testWidgets('guest gets the save prompt instead of an order insert',
      (tester) async {
    // Shared save-prompt sheet needs more room than the default surface.
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _FakeOrdersRepo();
    await _pump(tester,
        authState: const AuthState(phase: AuthPhase.guest), repo: repo);

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('تأكيد الطلب · 95 ج.م'));
    await tester.pumpAndSettle();

    expect(find.text('خلي نقاطك معاك!'), findsOneWidget);
    expect(repo.placeOrderCalls, 0);
  });

  testWidgets('double-tap while in flight inserts only once', (tester) async {
    final repo = _FakeOrdersRepo()..holdNextSubmit();
    await _pump(tester, authState: _ready, repo: repo);

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('تأكيد الطلب · 95 ج.م'));
    await tester.pump();

    expect(repo.placeOrderCalls, 1);
    // Busy state swaps the label for a spinner and disables the button;
    // a second tap is a no-op.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(repo.placeOrderCalls, 1);

    repo.releaseSubmit();
    await tester.pumpAndSettle();
    expect(repo.placeOrderCalls, 1);
  });

  testWidgets('successful submit lands on confirmation with DB display number',
      (tester) async {
    final repo = _FakeOrdersRepo();
    await _pump(tester, authState: _ready, repo: repo);

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('تأكيد الطلب · 95 ج.م'));
    await tester.pumpAndSettle();

    expect(repo.placeOrderCalls, 1);
    final order = repo.lastOrder!;
    expect(order.mode, OrderMode.dineIn);
    expect(order.googleUserId, 'g1');
    expect(order.phone, '+201000000000');
    expect(order.tableArea, 'رقم الترابيزة 12');
    expect(order.pickupSlotUtc, isNull);
    expect(order.addressId, isNull);
    expect(order.subtotalEgp, 95);
    expect(order.deliveryFeeEgp, 0);
    expect(order.totalEgp, 95);
    expect(order.pointsPreview, 10);
    expect(order.items, hasLength(2));
    final firstItem = order.items.first.toJson();
    expect(firstItem['id'], 'tea');
    expect(firstItem['qty'], 2);
    expect((firstItem['config'] as Map)['size'], 0);

    // Confirmation screen rendered from the returned display number.
    expect(find.text('#1023'), findsOneWidget);
    expect(find.text('تم تأكيد طلبك!'), findsOneWidget);
    expect(find.textContaining('~10 دقائق'), findsOneWidget);
    expect(find.text('صالة'), findsWidgets);

    // Below-the-fold list content: scroll the summary into view.
    await tester.dragUntilVisible(
      find.text('الدفع في الكافيه نقداً'),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();

    expect(find.text('الدفع في الكافيه نقداً'), findsOneWidget);
    expect(find.text('هذا الطلب يضيف 10 نقطة لحسابك ☕'), findsOneWidget);
    expect(find.text('رسوم التوصيل'), findsNothing);
    await tester.dragUntilVisible(
      find.text('تتبع الطلب'),
      find.byType(ListView),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    expect(find.text('تتبع الطلب'), findsOneWidget);
  });

  testWidgets('pickup renders totals without fee and succeeds without table', (tester) async {
    final repo = _FakeOrdersRepo();
    await _pumpWithDraft(tester, authState: _ready, repo: repo, draftBuilder: () => const CheckoutDraft(mode: OrderMode.pickup));
    expect(find.text('95 ج.م'), findsNWidgets(2));
    expect(find.text('رسوم التوصيل'), findsNothing);
    expect(find.text('استلام'), findsWidgets);
    await tester.tap(find.text('تأكيد الطلب · 95 ج.م'));
    await tester.pumpAndSettle();
    expect(repo.placeOrderCalls, 1);
    expect(repo.lastOrder!.mode, OrderMode.pickup);
    expect(repo.lastOrder!.deliveryFeeEgp, 0);
    expect(repo.lastOrder!.totalEgp, 95);
    expect(repo.lastOrder!.pickupSlotUtc, isNull);
  });

  testWidgets('delivery renders fee row and total includes fee, address required', (tester) async {
    final repo = _DeliveryFakeRepo();
    await _pumpWithDraft(tester, authState: _ready, repo: repo, draftBuilder: () => const CheckoutDraft(mode: OrderMode.delivery, addressId: 'addr-1'));
    // subtotal 95, fee 15, total 110
    expect(find.text('95 ج.م'), findsOneWidget);
    expect(find.text('15 ج.م'), findsOneWidget);
    expect(find.text('110 ج.م'), findsOneWidget);
    expect(find.text('رسوم التوصيل'), findsOneWidget);
    await tester.tap(find.text('تأكيد الطلب · 110 ج.م'));
    await tester.pumpAndSettle();
    expect(repo.placeOrderCalls, 1);
    expect(repo.lastOrder!.mode, OrderMode.delivery);
    expect(repo.lastOrder!.deliveryFeeEgp, 15);
    expect(repo.lastOrder!.totalEgp, 110);
    expect(repo.lastOrder!.addressId, 'addr-1');
  });

  testWidgets('delivery without address blocks submit', (tester) async {
    final repo = _DeliveryFakeRepo();
    await _pumpWithDraft(tester, authState: _ready, repo: repo, draftBuilder: () => const CheckoutDraft(mode: OrderMode.delivery));
    await tester.tap(find.text('تأكيد الطلب · 110 ج.م'));
    await tester.pumpAndSettle();
    expect(find.text('لازم تختار عنوان التوصيل الأول'), findsOneWidget);
    expect(repo.placeOrderCalls, 0);
  });

  testWidgets('pickup with future slot persists slotUtc', (tester) async {
    final repo = _FakeOrdersRepo();
    final slot = DateTime.utc(2026, 8, 30, 12, 0);
    await _pumpWithDraft(tester, authState: _ready, repo: repo, draftBuilder: () => CheckoutDraft(mode: OrderMode.pickup, pickupTiming: PickupTiming.slot(slot)));
    await tester.tap(find.text('تأكيد الطلب · 95 ج.م'));
    await tester.pumpAndSettle();
    expect(repo.placeOrderCalls, 1);
    expect(repo.lastOrder!.pickupSlotUtc, slot);
  });

  testWidgets('submit failure shows snackbar and keeps form', (tester) async {
    final repo = _FailingOrdersRepo();
    await _pump(tester, authState: _ready, repo: repo);
    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('تأكيد الطلب · 95 ج.م'));
    await tester.pumpAndSettle();
    expect(repo.placeOrderCalls, 1);
    // error snackbar (submitFailed) — Arabic copy
    expect(find.text('فشل إرسال الطلب — حاول تاني'), findsOneWidget);
    // form still present, button re-enabled
    expect(find.text('تأكيد الطلب · 95 ج.م'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
