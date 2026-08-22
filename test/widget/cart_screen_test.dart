// Widget tests for the cart tab (issue #003): line rendering with modifier
// summary and steppers, sticky subtotal, guest gate on متابعة الدفع
// (RLS forbids guest orders) and the signed-in path to /mode-selection.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/domain/auth_controller.dart';
import 'package:kady_app/domain/cart_controller.dart';
import 'package:kady_app/ui/cart/cart_screen.dart';

const _latte = MenuItem(
  id: 'latte',
  slug: 'latte',
  nameAr: 'لاتيه',
  nameEn: 'Latte',
  descAr: '',
  descEn: '',
  priceEgp: 45,
  isAvailable: true,
  categorySlug: 'hot',
);

class _FixedAuth extends AuthController {
  _FixedAuth(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/cart',
    routes: [
      GoRoute(
        path: '/cart',
        builder: (_, _) => const CartScreen(),
      ),
      GoRoute(
        path: '/menu',
        builder: (_, _) => const Scaffold(body: Text('MENU_STUB')),
      ),
      GoRoute(
        path: '/mode-selection',
        builder: (_, _) => const Scaffold(body: Text('MODES_STUB')),
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester,
    {required AuthState authState}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _FixedAuth(authState)),
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
  await tester.pumpAndSettle();
}

void main() {
  const ready = AuthState(
    phase: AuthPhase.ready,
    googleUser: GoogleProfile(id: 'g1'),
    phone: '+201000000000',
  );

  testWidgets('guest tapping متابعة الدفع gets the save prompt, not checkout',
      (tester) async {
    // The shared save-prompt sheet is tight on the default 800×600 test
    // surface (pre-existing component); give it room.
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, authState: const AuthState(phase: AuthPhase.guest));
    _seedCart(tester);

    await tester.pumpAndSettle();
    expect(find.text('متابعة الدفع'), findsOneWidget);

    await tester.tap(find.text('متابعة الدفع'));
    await tester.pumpAndSettle();

    // Save-progress prompt opened; no mode selection navigation happened.
    expect(find.text('خلي نقاطك معاك!'), findsOneWidget);
    expect(find.text('MODES_STUB'), findsNothing);
  });

  testWidgets('signed-in customer continues to mode selection', (tester) async {
    await _pump(tester, authState: ready);
    _seedCart(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('متابعة الدفع'));
    await tester.pumpAndSettle();

    expect(find.text('MODES_STUB'), findsOneWidget);
    expect(find.text('خلي نقاطك معاك!'), findsNothing);
  });
  testWidgets('line shows modifiers summary + note; steppers update subtotal',
      (tester) async {
    await _pump(tester, authState: ready);
    _seedCart(
      tester,
      config: const ItemConfig(
        sizeIndex: 1,
        sugarIndex: 0,
        addons: {'caramel'},
        note: 'سكر زيادة',
      ),
    );
    await tester.pumpAndSettle();

    // Unit 45 + 10 medium + 10 caramel = 65 EGP × 2 = 130.
    expect(find.text('وسط · كراميل'), findsOneWidget);
    expect(find.text('“سكر زيادة”'), findsOneWidget);
    // Line total + sticky footer subtotal both read 130 ج.م.
    expect(find.text('130 ج.م'), findsNWidgets(2));

    await tester.tap(find.byTooltip('زيادة الكمية'));
    await tester.pumpAndSettle();
    expect(find.text('195 ج.م'), findsNWidgets(2));

    await tester.tap(find.byTooltip('إزالة من السلة'));
    await tester.pumpAndSettle();
    expect(find.text('سلّتك فاضية'), findsOneWidget);
    expect(find.text('تصفح القائمة'), findsOneWidget);
  });

  testWidgets('empty cart offers a menu CTA that navigates', (tester) async {
    await _pump(tester, authState: ready);
    await tester.pumpAndSettle();

    expect(find.text('سلّتك فاضية'), findsOneWidget);
    await tester.tap(find.text('تصفح القائمة'));
    await tester.pumpAndSettle();
    expect(find.text('MENU_STUB'), findsOneWidget);
  });
}

/// Seeds one latte line into the cart after the first frame exists.
void _seedCart(WidgetTester tester, {ItemConfig config = const ItemConfig()}) {
  final element = tester.element(find.byType(CartScreen));
  final container = ProviderScope.containerOf(element);
  container.read(cartProvider.notifier).addItem(_latte, config, qty: 2);
}
