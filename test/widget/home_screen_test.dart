// Widget tests for the customer home hub (issue #005): greeting + tier chip,
// points progress toward the 200-pt reward, stamp slots, quick actions,
// banner swipe/auto-advance, dev boost sheet, guest zeros + register link,
// and the active-order strip fed by order_queries probes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kady_app/data/repos/order_queries.dart';
import 'package:kady_app/domain/auth_controller.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
import 'package:kady_app/domain/session_controller.dart';
import 'package:kady_app/ui/home/home_screen.dart';
import 'package:kady_app/ui/home/widgets/banner_carousel.dart';

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

class _FixedSession extends SessionController {
  _FixedSession(this._state);

  final SessionState _state;

  @override
  SessionState build() => _state;
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/menu',
        builder: (_, _) => const Scaffold(body: Text('MENU_STUB')),
      ),
      GoRoute(
        path: '/games',
        builder: (_, _) => const Scaffold(body: Text('GAMES_STUB')),
      ),
      GoRoute(
        path: '/games/spinner',
        builder: (_, _) => const Scaffold(body: Text('SPINNER_STUB')),
      ),
      GoRoute(
        path: '/games/match',
        builder: (_, _) => const Scaffold(body: Text('MATCH_STUB')),
      ),
      GoRoute(
        path: '/games/scratch',
        builder: (_, _) => const Scaffold(body: Text('SCRATCH_STUB')),
      ),
      GoRoute(
        path: '/games/quests',
        builder: (_, _) => const Scaffold(body: Text('QUESTS_STUB')),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('PROFILE_STUB')),
      ),
      GoRoute(
        path: '/orders',
        builder: (_, _) => const Scaffold(body: Text('ORDERS_STUB')),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, _) => const Scaffold(body: Text('ORDER_STATUS_STUB')),
      ),
      GoRoute(
        path: '/mode-selection',
        builder: (_, _) => const Scaffold(body: Text('MODES_STUB')),
      ),
      GoRoute(
        path: '/staff/lookup',
        builder: (_, _) => const Scaffold(body: Text('STAFF_LOOKUP_STUB')),
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required AuthState authState,
  LoyaltyState loyalty = const LoyaltyState(),
  List<Map<String, dynamic>> activeOrders = const [],
  AppRole sessionRole = AppRole.customer,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _FixedAuth(authState)),
        loyaltyProvider.overrideWith(() => _FixedLoyalty(loyalty)),
        sessionControllerProvider.overrideWith(
          () => _FixedSession(SessionState(role: sessionRole)),
        ),
        activeOrdersFetcherProvider.overrideWith(
          (ref) => (String phone) async => activeOrders,
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
  // First frame + post-frame active-orders probe resolution.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

const _readyAuth = AuthState(
  phase: AuthPhase.ready,
  googleUser: GoogleProfile(id: 'g1', name: 'مصطفى محمود'),
  phone: '+201000000000',
);

const _demoLoyalty = LoyaltyState(points: 120, lifetimePoints: 120, stamps: 7);

void main() {
  testWidgets('signed-in hub greets by first name with bronze chip and 120/200 progress',
      (tester) async {
    await _pump(tester, authState: _readyAuth, loyalty: _demoLoyalty);

    expect(find.text('أهلاً مصطفى 👋'), findsOneWidget);
    expect(find.text('برونزي'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('نقطة'), findsOneWidget);
    expect(find.text('120 / 200'), findsOneWidget);
    expect(find.text('→ مشروب مجاني'), findsOneWidget);
  });

  testWidgets('stamp card fills 7 of 10 slots and badges completed cards',
      (tester) async {
    await _pump(
      tester,
      authState: _readyAuth,
      loyalty: const LoyaltyState(
        points: 120,
        lifetimePoints: 120,
        stamps: 7,
        completedCards: 1,
      ),
    );

    expect(find.text('☕'), findsNWidgets(7));
    expect(find.text('7 / 10 زيارة → سناكس مجاني'), findsOneWidget);
    expect(find.text('1 بطاقة مكتملة'), findsOneWidget);
  });

  testWidgets('quick actions render and اطلب دلوقتي navigates to mode selection',
      (tester) async {
    await _pump(tester, authState: _readyAuth, loyalty: _demoLoyalty);

    expect(find.text('اطلب دلوقتي'), findsOneWidget);
    expect(find.text('امسح واكسب'), findsOneWidget);
    expect(find.text('العب'), findsOneWidget);
    expect(find.text('المكافآت'), findsOneWidget);

    await tester.tap(find.text('اطلب دلوقتي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MODES_STUB'), findsOneWidget);
  });

  testWidgets('banners swipe forward and auto-advance on the 5s cadence',
      (tester) async {
    await _pump(tester, authState: _readyAuth, loyalty: _demoLoyalty);

    int activeIndex() => tester
        .widget<HomeDotsIndicator>(find.byType(HomeDotsIndicator))
        .activeIndex;

    expect(find.byType(PageView), findsOneWidget);
    expect(activeIndex(), 0);

    // RTL: content flows right→left, so a +dx drag reveals the next banner.
    await tester.drag(find.byType(PageView), const Offset(480, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(activeIndex(), 1);

    // Auto-advance tick (timer restarted after the drag's pointer-up).
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(activeIndex(), 2);
  });

  
  testWidgets('guest hub shows generic greeting, zeros and register link → save prompt',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, authState: const AuthState(phase: AuthPhase.guest));

    expect(find.text('أهلاً بيك في القاضي'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.byKey(const Key('home_dev_boost_open')), findsNothing);
    expect(find.byKey(const Key('home_active_order_strip')), findsNothing);

    await tester.tap(find.byKey(const Key('home_guest_register')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('خلي نقاطك معاك!'), findsOneWidget);
  });

  testWidgets('active order strip shows the newest in-flight order',
      (tester) async {
    await _pump(
      tester,
      authState: _readyAuth,
      loyalty: _demoLoyalty,
      activeOrders: const [
        {'id': 'o1', 'display_number': 1023, 'status': 'in_prep', 'mode': 'pickup'},
      ],
    );

    expect(find.byKey(const Key('home_active_order_strip')), findsOneWidget);
    expect(find.text('طلبك #1023 — قيد التحضير'), findsOneWidget);
  });

  testWidgets('active order strip tap navigates to /orders', (tester) async {
    await _pump(
      tester,
      authState: _readyAuth,
      loyalty: _demoLoyalty,
      activeOrders: const [
        {'id': 'o1', 'display_number': 1023, 'status': 'in_prep', 'mode': 'pickup'},
      ],
    );

    await tester.tap(find.byKey(const Key('home_active_order_strip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ORDERS_STUB'), findsOneWidget);
    expect(find.text('قريبًا'), findsNothing);
  });

  testWidgets(
      'quick action امسح واكسب — customer shows comingSoon SnackBar (FEATURES §6)',
      (tester) async {
    await _pump(tester, authState: _readyAuth, loyalty: _demoLoyalty);

    expect(find.text('امسح واكسب'), findsOneWidget);
    await tester.tap(find.text('امسح واكسب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('قريبًا'), findsOneWidget);
    expect(find.text('MENU_STUB'), findsNothing);
    expect(find.text('STAFF_LOOKUP_STUB'), findsNothing);
  });

  testWidgets('quick action امسح واكسب — staff routes to /staff/lookup',
      (tester) async {
    await _pump(
      tester,
      authState: _readyAuth,
      loyalty: _demoLoyalty,
      sessionRole: AppRole.staff,
    );

    expect(find.text('امسح واكسب'), findsOneWidget);
    await tester.tap(find.text('امسح واكسب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('STAFF_LOOKUP_STUB'), findsOneWidget);
    expect(find.text('قريبًا'), findsNothing);
  });

  testWidgets('banner tap navigates to /games/quests', (tester) async {
    await _pump(tester, authState: _readyAuth, loyalty: _demoLoyalty);

    // First banner card key is home_banner_0.
    expect(find.byKey(const ValueKey('home_banner_0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_banner_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('QUESTS_STUB'), findsOneWidget);
    expect(find.text('قريبًا'), findsNothing);
  });

  testWidgets('quick action Play still navigates to /games', (tester) async {
    await _pump(tester, authState: _readyAuth, loyalty: _demoLoyalty);

    await tester.tap(find.text('العب'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('GAMES_STUB'), findsOneWidget);
  });

  testWidgets('quick action المكافآت still navigates to /profile', (tester) async {
    await _pump(tester, authState: _readyAuth, loyalty: _demoLoyalty);

    await tester.tap(find.text('المكافآت'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PROFILE_STUB'), findsOneWidget);
  });
}
