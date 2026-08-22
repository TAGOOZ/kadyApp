import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/auth_controller.dart';
import '../domain/session_controller.dart';
import 'l10n/app_strings.dart';
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
import '../ui/screens/auth_stub_screen.dart';
import '../ui/screens/placeholder_page.dart';
import '../ui/screens/welcome_screen.dart';

enum _CustomerTab { home, menu, games, profile }

extension _CustomerTabX on _CustomerTab {
  String title(Strings s) {
    return switch (this) {
      _CustomerTab.home => s.tabHome,
      _CustomerTab.menu => s.tabMenu,
      _CustomerTab.games => s.tabGames,
      _CustomerTab.profile => s.tabProfile,
    };
  }

  String line(Strings s) {
    return switch (this) {
      _CustomerTab.home => s.homeLine,
      _CustomerTab.menu => s.menuLine,
      _CustomerTab.games => s.gamesLine,
      _CustomerTab.profile => s.profileLine,
    };
  }
}

String _homeFor(AppRole role) {
  return switch (role) {
    AppRole.customer => '/home',
    AppRole.staff => '/staff',
    AppRole.driver => '/driver',
    AppRole.admin => '/admin',
  };
}

class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(Ref ref) {
    ref.listen(sessionControllerProvider, (_, _) {
      if (!_disposed) {
        notifyListeners();
      }
    });
    ref.listen(authControllerProvider, (_, _) {
      if (!_disposed) {
        notifyListeners();
      }
    });
    ref.onDispose(() => _disposed = true);
  }

  bool _disposed = false;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  final router = GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      // Google OAuth gate: post-sign-in phone collection is mandatory.
      if (auth.phase == AuthPhase.authedWithoutPhone) {
        return location == '/auth/phone' ? null : '/auth/phone';
      }
      // Welcome gate only applies while unauthenticated (idle).
      if (!session.onboarded && auth.phase == AuthPhase.idle) {
        return location == '/welcome' ? null : '/welcome';
      }
      if (location == '/' ||
          location == '/welcome' ||
          location == '/auth/phone') {
        return _homeFor(session.role);
      }
      const customerPaths = [
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
      if (customerPaths.any(location.startsWith)) {
        return session.role == AppRole.customer
            ? null
            : _homeFor(session.role);
      }
      if ((location.startsWith('/staff') && session.role != AppRole.staff) ||
          (location.startsWith('/driver') && session.role != AppRole.driver) ||
          (location.startsWith('/admin') && session.role != AppRole.admin)) {
        return _homeFor(session.role);
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      // TODO(slice-004): real Google OAuth flow replaces this unused stub.
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthStubScreen(),
      ),
      GoRoute(
        path: '/auth/phone',
        builder: (context, state) => const PhoneCollectionScreen(),
      ),
      // Checkout flow (issue #003) — pushed above the customer shell.
      GoRoute(
        path: '/cart',
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: '/mode-selection',
        builder: (context, state) => const ModeSelectionScreen(),
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: '/confirmation',
        builder: (context, state) => const OrderConfirmationScreen(),
      ),
      // Orders slice (#006): live list + per-order status timeline.
      GoRoute(
        path: '/orders',
        builder: (context, state) => const OrdersListScreen(),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) => OrderStatusScreen(
          orderId: state.pathParameters['id']!,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(
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
                builder: (context, state) =>
                    const _PlaceholderTab(_CustomerTab.games),
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
        path: '/staff',
        builder: (context, state) => const _RoleDashboardScreen(),
      ),
      GoRoute(
        path: '/driver',
        builder: (context, state) => const _RoleDashboardScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const _RoleDashboardScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _PlaceholderTab extends ConsumerWidget {
  const _PlaceholderTab(this.tab);

  final _CustomerTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = AppStrings.of(lang);
    return PlaceholderPage(
      title: tab.title(strings),
      line: tab.line(strings),
      showRoleTile: tab == _CustomerTab.profile,
    );
  }
}

class _RoleDashboardScreen extends ConsumerWidget {
  const _RoleDashboardScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final strings = AppStrings.of(session.lang);
    final roleLabel = roleNameOf(session.role, strings);

    return PlaceholderPage(
      title: strings.dashboardTitle(roleLabel),
      line: strings.dashboardHint,
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
