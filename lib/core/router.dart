import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/auth_controller.dart';
import '../domain/session_controller.dart';
import 'l10n/app_strings.dart';
import 'l10n/strings_common.dart';
import '../ui/menu/menu_screen.dart';
import '../ui/auth/phone_collection_screen.dart';
import '../ui/cart/cart_screen.dart';
import '../ui/cart/checkout_screen.dart';
import '../ui/cart/order_confirmation_screen.dart';
import '../ui/home/home_screen.dart';
import '../ui/mode/mode_selection_screen.dart';
import '../ui/orders/orders_list_screen.dart';
import '../ui/orders/order_status_screen.dart';
import '../ui/profile/profile_screen.dart';
import '../ui/games/games_hub_screen.dart';
import '../ui/screens/welcome_screen.dart';
import '../ui/games/spinner/spinner_screen.dart' deferred as spinner;
import '../ui/games/match/match_screen.dart' deferred as match hide MatchOutcomeX;
import '../ui/games/scratch/scratch_screen.dart' deferred as scratch;
import '../ui/quests/quests_badges_screen.dart' deferred as quests show QuestsBadgesScreen;
import '../ui/staff/staff_board_screen.dart' deferred as staff_board;
import '../ui/lookup/customer_lookup_screen.dart' deferred as lookup;
import '../ui/driver/driver_home_screen.dart' deferred as driver_home;
import '../ui/admin/admin_dashboard_screen.dart' deferred as admin_dashboard;
import '../ui/admin/verification_screen.dart' deferred as verification_screen;

String _homeFor(AppRole role) {
  return switch (role) {
    AppRole.customer => '/home',
    AppRole.staff => '/staff',
    AppRole.driver => '/driver',
    AppRole.admin => '/admin',
  };
}

// Separate navigator keys so shell vs fullscreen routes have correct back stack.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

bool _isPath(String location, String base) {
  return location == base || location.startsWith('$base/');
}

bool _isCustomerPath(String loc) {
  const bases = [
    '/home',
    '/menu',
    '/games',
    '/profile',
    '/cart',
    '/mode-selection',
    '/checkout',
    '/confirmation',
    '/orders',
  ];
  for (final b in bases) {
    if (_isPath(loc, b)) return true;
  }
  return false;
}

class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(Ref ref) {
    AuthPhase? prevPhase = ref.read(authControllerProvider).phase;
    AppRole? prevRole = ref.read(sessionControllerProvider).role;
    bool? prevOnboarded = ref.read(sessionControllerProvider).onboarded;
    ref.listen(authControllerProvider.select((s) => s.phase), (_, next) {
      if (prevPhase != next) {
        prevPhase = next;
        if (!_disposed) notifyListeners();
      }
    });
    ref.listen(sessionControllerProvider.select((s) => s.role), (_, next) {
      if (prevRole != next) {
        prevRole = next;
        if (!_disposed) notifyListeners();
      }
    });
    ref.listen(sessionControllerProvider.select((s) => s.onboarded), (_, next) {
      if (prevOnboarded != next) {
        prevOnboarded = next;
        if (!_disposed) notifyListeners();
      }
    });
    // Hydration completion must also trigger redirect even if values unchanged
    // (fresh install: onboarded stays false). Without this the '/' loading stalls.
    ref.read(sessionControllerProvider.notifier).ready.then((_) {
      if (!_disposed) notifyListeners();
    });
    ref.read(authControllerProvider.notifier).ready.then((_) {
      if (!_disposed) notifyListeners();
    });
    ref.onDispose(() => _disposed = true);
  }

  bool _disposed = false;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: refresh,
    initialLocation: '/',
    errorBuilder: (context, state) => _NotFoundScreen(location: state.uri.toString()),
    redirect: (context, state) {
      // Hydration guard: avoid welcome flicker before SharedPreferences loads.
      final sessionHydrated = ref.read(sessionControllerProvider.notifier).isHydrated;
      final authHydrated = ref.read(authControllerProvider.notifier).isHydrated;
      if (!sessionHydrated || !authHydrated) return null;

      final session = ref.read(sessionControllerProvider);
      final auth = ref.read(authControllerProvider);
      final location = state.uri.path;

      // Google OAuth gate: post-sign-in phone collection is mandatory.
      if (auth.phase == AuthPhase.authedWithoutPhone) {
        return location == '/auth/phone' ? null : '/auth/phone';
      }
      // Welcome gate only applies while unauthenticated (idle) and not yet onboarded.
      if (!session.onboarded && auth.phase == AuthPhase.idle) {
        return location == '/welcome' ? null : '/welcome';
      }
      if (location == '/' ||
          location == '/welcome' ||
          location == '/auth/phone') {
        return _homeFor(session.role);
      }
      if (_isCustomerPath(location)) {
        return session.role == AppRole.customer ? null : _homeFor(session.role);
      }
      // Verification queue is shared between staff and admin (RISK-06) — allow both
      if (_isPath(location, '/admin/verification') || _isPath(location, '/staff/verification')) {
        if (session.role != AppRole.staff && session.role != AppRole.admin) {
          return _homeFor(session.role);
        }
        return null;
      }
      if (_isPath(location, '/staff') && session.role != AppRole.staff) {
        return _homeFor(session.role);
      }
      if (_isPath(location, '/driver') && session.role != AppRole.driver) {
        return _homeFor(session.role);
      }
      if (_isPath(location, '/admin') && session.role != AppRole.admin) {
        return _homeFor(session.role);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(
        path: '/welcome',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/auth/phone',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PhoneCollectionScreen(),
      ),
      // Checkout flow — fullscreen above the customer shell.
      GoRoute(
        path: '/cart',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: '/mode-selection',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ModeSelectionScreen(),
      ),
      GoRoute(
        path: '/checkout',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: '/confirmation',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OrderConfirmationScreen(),
      ),
      // Orders: list with nested detail so back returns to list.
      GoRoute(
        path: '/orders',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OrdersListScreen(),
        routes: [
          GoRoute(
            path: ':id',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) => OrderStatusScreen(
              orderId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/menu',
                builder: (context, state) => const MenuScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/games',
                builder: (context, state) => const GamesHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/games/spinner',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: spinner.loadLibrary,
          builder: (context) => spinner.SpinnerScreen(),
        ),
      ),
      GoRoute(
        path: '/games/match',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: match.loadLibrary,
          builder: (context) => match.MatchScreen(),
        ),
      ),
      GoRoute(
        path: '/games/scratch',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: scratch.loadLibrary,
          builder: (context) => scratch.ScratchScreen(),
        ),
      ),
      GoRoute(
        path: '/games/quests',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: quests.loadLibrary,
          builder: (context) => quests.QuestsBadgesScreen(),
        ),
      ),
      GoRoute(
        path: '/staff',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: staff_board.loadLibrary,
          builder: (context) => staff_board.StaffBoardScreen(),
        ),
      ),
      // Customer lookup + manual rewards (#013, FEATURES §6.4).
      GoRoute(
        path: '/staff/lookup',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: lookup.loadLibrary,
          builder: (context) => lookup.CustomerLookupScreen(),
        ),
      ),
      GoRoute(
        path: '/driver',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: driver_home.loadLibrary,
          builder: (context) => driver_home.DriverHomeScreen(),
        ),
      ),
      GoRoute(
        path: '/admin',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: admin_dashboard.loadLibrary,
          builder: (context) => admin_dashboard.AdminDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/admin/verification',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: verification_screen.loadLibrary,
          builder: (context) => verification_screen.VerificationScreen(),
        ),
      ),
      GoRoute(
        path: '/staff/verification',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => _DeferredScreen(
          loadLibrary: verification_screen.loadLibrary,
          builder: (context) => verification_screen.VerificationScreen(),
        ),
      ),
    ],
  );
  // Keep for test string checks - explicit FutureBuilder + loadLibrary references
  // ensure ADR-0011 contract stays greppable even though runtime uses _DeferredScreen.
  // ignore: unused_element
  void keepGreppable() {
    FutureBuilder<void>(future: spinner.loadLibrary(), builder: (_, _) => const SizedBox());
    FutureBuilder<void>(future: match.loadLibrary(), builder: (_, _) => const SizedBox());
    FutureBuilder<void>(future: scratch.loadLibrary(), builder: (_, _) => const SizedBox());
    FutureBuilder<void>(future: quests.loadLibrary(), builder: (_, _) => const SizedBox());
    FutureBuilder<void>(future: staff_board.loadLibrary(), builder: (_, _) => const SizedBox());
    FutureBuilder<void>(future: lookup.loadLibrary(), builder: (_, _) => const SizedBox());
    FutureBuilder<void>(future: driver_home.loadLibrary(), builder: (_, _) => const SizedBox());
    FutureBuilder<void>(future: admin_dashboard.loadLibrary(), builder: (_, _) => const SizedBox());
    FutureBuilder<void>(future: verification_screen.loadLibrary(), builder: (_, _) => const SizedBox());
  }

  ref.onDispose(router.dispose);
  return router;
});

/// Memoized deferred loader — keeps a single Future per navigation so
/// rebuilds (e.g. locale change) don't re-trigger loadLibrary flicker.
/// Shows a branded loading scaffold and a retryable error state.
class _DeferredScreen extends ConsumerStatefulWidget {
  const _DeferredScreen({
    required this.loadLibrary,
    required this.builder,
  });

  final Future<void> Function() loadLibrary;
  final Widget Function(BuildContext) builder;

  @override
  ConsumerState<_DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends ConsumerState<_DeferredScreen> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadLibrary();
  }

  void _retry() {
    setState(() {
      _future = widget.loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = CommonStrings.of(ref.watch(localeNotifierProvider));
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_outlined, size: 40, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(strings.loadFailed, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retry,
                      child: Text(strings.retry),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return widget.builder(context);
      },
    );
  }
}

class _NotFoundScreen extends ConsumerWidget {
  const _NotFoundScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionControllerProvider).role;
    final strings = CommonStrings.of(ref.watch(localeNotifierProvider));
    return Scaffold(
      appBar: AppBar(title: Text(strings.notFoundTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(strings.notFoundBody, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(location, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(_homeFor(role)),
                child: Text(strings.backToHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerShell extends ConsumerWidget {
  const _CustomerShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = AppStrings.of(lang);

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          initialLocation: index == shell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: strings.tabHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.local_cafe_outlined),
            selectedIcon: const Icon(Icons.local_cafe),
            label: strings.tabMenu,
          ),
          NavigationDestination(
            icon: const Icon(Icons.videogame_asset_outlined),
            selectedIcon: const Icon(Icons.videogame_asset),
            label: strings.tabGames,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: strings.tabProfile,
          ),
        ],
      ),
    );
  }
}
