// Customer home hub (#005, FEATURES §3.2): greeting + tier chip, points card,
// stamp card, quick actions, campaign banners and the active-order strip —
// all inside a pull-to-refresh scroll. Guest mode renders the same hub with
// zeros and a register link instead of dev affordances.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_home.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/order_queries.dart';
import '../../domain/auth_controller.dart';
import '../../domain/loyalty_controller.dart';
import 'widgets/active_order_strip.dart';
import 'widgets/banner_carousel.dart';
import 'widgets/greeting_header.dart';
import 'widgets/points_card.dart';
import 'widgets/quick_actions_row.dart';
import 'widgets/stamp_card_widget.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Map<String, dynamic>> _activeOrders = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActiveOrders());
  }

  Future<void> _loadActiveOrders() async {
    final auth = ref.read(authControllerProvider);
    if (auth.phase != AuthPhase.ready || (auth.phone ?? '').isEmpty) {
      if (mounted && _activeOrders.isNotEmpty) {
        setState(() => _activeOrders = const []);
      }
      return;
    }
    final rows = await ref.read(activeOrdersFetcherProvider)(auth.phone!);
    if (!mounted) return;
    setState(() => _activeOrders = rows);
  }

  Future<void> _refresh() => _loadActiveOrders();

  void _comingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = HomeStringsCatalog.of(lang);
    final auth = ref.watch(authControllerProvider);
    final loyalty = ref.watch(loyaltyProvider);
    final signedIn = auth.phase == AuthPhase.ready;

    final googleName = auth.googleUser?.name.trim() ?? '';
    final firstName =
        signedIn && googleName.isNotEmpty ? googleName.split(' ').first : '';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.margin20,
              AppSpacing.xs8,
              AppSpacing.margin20,
              AppSpacing.md24,
            ),
            children: [
              GreetingHeader(
                firstName: firstName,
                tier: loyalty.tier,
                strings: strings,
                isGuest: !signedIn,
                onAvatarTap: () => context.go('/profile'),
              ),
              const SizedBox(height: AppSpacing.sm16),
              ActiveOrderStrip(
                orders: _activeOrders,
                strings: strings,
                onTap: () => _comingSoon(context, strings.comingSoon),
              ),
              const SizedBox(height: AppSpacing.sm16),
              PointsCard(
                key: const Key('home_points_card'),
                points: signedIn ? loyalty.points : 0,
                strings: strings,
                signedIn: signedIn,
              ),
              const SizedBox(height: AppSpacing.sm16),
              StampCardWidget(
                stamps: signedIn ? loyalty.stamps : 0,
                completedCards: signedIn ? loyalty.completedCards : 0,
                strings: strings,
              ),
              const SizedBox(height: AppSpacing.sm16),
              QuickActionsRow(
                strings: strings,
                onComingSoon: () => _comingSoon(context, strings.comingSoon),
              ),
              const SizedBox(height: AppSpacing.md24),
              BannerCarousel(
                strings: strings,
                autoAdvance: kBannerAutoAdvance,
                onTapBanner: () => _comingSoon(context, strings.comingSoon),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
