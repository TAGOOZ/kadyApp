// Widget tests for the #007 checkout redemption hook: the loyalty box gains a
// points-redemption toggle only when an affordable reward exists, a free
// drink zeroes the highest-priced drink line in the displayed totals, the
// remaining-points preview updates, and submission encodes the redemption as
// a `[REDEEMED:{type}:{cost}]` notes prefix while placing the order on the
// discounted subtotal. All Supabase traffic goes through fakes/overrides —
// no network (the real crediting call degrades to optimistic local state).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/orders_repository.dart';
import 'package:kady_app/domain/auth_controller.dart';
import 'package:kady_app/domain/risk_engine.dart';
import 'package:kady_app/domain/cart_controller.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
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
  categorySlug: 'hot_drinks', // seeded slug vocabulary (#007)
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
    return const PlacedOrder(id: 'order-xyz', displayNumber: 1023);
  }

  @override
  Future<RiskResult> previewRisk(NewOrder draft) async =>
      const RiskResult(score: 0, level: RiskLevel.low, reasons: [], action: RiskAction.approved);
}

class _FixedAuth extends AuthController {
  _FixedAuth(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

class _FixedLoyalty extends LoyaltyController {
  _FixedLoyalty(this._state);

  final LoyaltyState _state;

  @override
  LoyaltyState build() => _state;
}

class _DineInDraft extends CheckoutDraftController {
  @override
  CheckoutDraft build() => const CheckoutDraft(mode: OrderMode.dineIn);
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

Future<void> _pump(
  WidgetTester tester, {
  required LoyaltyState loyaltyState,
  OrdersRepo? repo,
}) async {
  final fakeRepo = repo ?? _FakeOrdersRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersRepoProvider.overrideWithValue(fakeRepo),
        authControllerProvider.overrideWith(
          () => _FixedAuth(const AuthState(
            phase: AuthPhase.ready,
            googleUser: GoogleProfile(id: 'g1'),
            phone: '+201000000000',
          )),
        ),
        checkoutDraftProvider.overrideWith(_DineInDraft.new),
        loyaltyProvider.overrideWith(() => _FixedLoyalty(loyaltyState)),
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

  // Seed the cart after the first frame: tea 40 + biscuit 15 = 55 EGP.
  final element = tester.element(find.byType(CheckoutScreen));
  final container = ProviderScope.containerOf(element);
  container.read(cartProvider.notifier).addItem(_tea, const ItemConfig());
  container.read(cartProvider.notifier).addItem(_biscuit, const ItemConfig());

  await tester.pumpAndSettle();
}

void main() {
  testWidgets('200 pts + drink line shows the drink toggle; zeroed line '
      'updates totals and remaining preview', (tester) async {
    await _pump(tester, loyaltyState: const LoyaltyState(points: 200));

    expect(find.text('استخدم 200 نقطة → مشروب مجاني'), findsOneWidget);
    // Before toggling: full subtotal everywhere.
    expect(find.text('55 ج.م'), findsNWidgets(2));

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Drink line (40 EGP) zeroed → subtotal + total drop to 15 ج.م.
    expect(find.text('15 ج.م'), findsNWidgets(2));
    expect(find.text('تأكيد الطلب · 15 ج.م'), findsOneWidget);
    // Remaining balance preview: 200 − 200 = 0.
    expect(find.text('رصيدك بعد الاستخدام: 0 نقطة'), findsOneWidget);
    // Earn preview recomputed on the discounted spend: 15×1.1/10=1.65→2.
    expect(find.text('هذا الطلب يضيف ~2 نقطة لحسابك ☕'), findsOneWidget);

    // Untoggle restores the undiscounted totals.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('55 ج.م'), findsNWidgets(2));
    expect(find.text('رصيدك بعد الاستخدام: 0 نقطة'), findsNothing);
  });

  testWidgets('insufficient points hide the toggle entirely', (tester) async {
    await _pump(tester, loyaltyState: const LoyaltyState(points: 99));

    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('استخدم'), findsNothing);
    expect(find.text('55 ج.م'), findsNWidgets(2));
  });

  testWidgets('topping tier applies without touching totals', (tester) async {
    await _pump(tester, loyaltyState: const LoyaltyState(points: 120));

    expect(find.text('استخدم 100 نقطة → توبينج مجاني'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Non-drink redemptions deduct points only — cash total unchanged.
    expect(find.text('55 ج.م'), findsNWidgets(2));
    expect(find.text('رصيدك بعد الاستخدام: 20 نقطة'), findsOneWidget);
  });

  testWidgets('submit encodes [REDEEMED] notes prefix and places the order '
      'on the discounted subtotal', (tester) async {
    final repo = _FakeOrdersRepo();
    await _pump(
      tester,
      loyaltyState: const LoyaltyState(points: 200),
      repo: repo,
    );

    await tester.enterText(find.byType(TextField), '12');
    // Seed whole-order notes through the shared draft controller.
    ProviderScope.containerOf(
      tester.element(find.byType(CheckoutScreen)),
    ).read(checkoutDraftProvider.notifier).setNotes('بدون سكر');
    await tester.tap(find.byType(Checkbox)); // redeem the drink line
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Remaining-points preview gone post-submit. NOTE (comment only): the
    // actual Points deduction is covered by the `creditRedeemedOrder` unit
    // tests in test/unit/loyalty_rules_test.dart — this harness's
    // `_FixedLoyalty` overrides build() and bypasses real state transitions,
    // so server-balance mutation is deliberately not asserted here.
    expect(find.text('رصيدك بعد الاستخدام: 0 نقطة'), findsNothing);

    expect(repo.placeOrderCalls, 1);
    final order = repo.lastOrder!;
    expect(order.subtotalEgp, 15); // 55 − 40 zeroed drink line
    expect(order.totalEgp, 15);
    expect(order.pointsPreview, 2);
    expect(order.tableArea, 'رقم الترابيزة 12');
    expect(order.notes,
        '[REDEEMED:free_drink:200] بدون سكر'); // prefix + user notes

    // Landed on confirmation with the discounted numbers.
    expect(find.text('#1023'), findsOneWidget);
  });
}
