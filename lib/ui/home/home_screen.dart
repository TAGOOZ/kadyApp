// Customer home hub (#005 v3, FEATURES §3.2) — hierarchy follows the single-brand
// café pattern (Starbucks/Damascus): greeting → in-flight order → merged loyalty
// hero (points + stamps on ONE surface) → single primary order CTA → 2×2
// secondary actions → featured discovery carousel → order-again strip → campaign
// banners, all inside a pull-to-refresh scroll. Categories live ONLY in the Menu
// tab — home surfaces curated discovery instead (featured / most-ordered).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_home.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/qr_checkin.dart';
import '../staff/widgets/qr_scanner_sheet.dart';
import '../../data/repos/order_queries.dart';
import '../../domain/auth_controller.dart';
import '../../domain/loyalty_controller.dart';
import '../../domain/session_controller.dart';
import 'widgets/active_order_strip.dart';
import 'widgets/banner_carousel.dart';
import 'widgets/featured_carousel.dart';
import 'widgets/greeting_header.dart';
import 'widgets/loyalty_hero_card.dart';
import 'widgets/order_again_strip.dart';
import 'widgets/quick_actions_row.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Map<String, dynamic>> _activeOrders = const [];
  Map<String, dynamic>? _lastCompletedOrder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHomeData());
  }

  Future<void> _loadHomeData() async {
    final auth = ref.read(authControllerProvider);
    if (auth.phase != AuthPhase.ready || (auth.phone ?? '').isEmpty) {
      if (mounted &&
          (_activeOrders.isNotEmpty || _lastCompletedOrder != null)) {
        setState(() {
          _activeOrders = const [];
          _lastCompletedOrder = null;
        });
      }
      return;
    }
    final results = await Future.wait([
      ref.read(activeOrdersFetcherProvider)(auth.phone!),
      ref.read(lastCompletedOrderFetcherProvider)(auth.phone!),
    ]);
    if (!mounted) return;
    setState(() {
      _activeOrders = results[0] as List<Map<String, dynamic>>;
      _lastCompletedOrder = results[1] as Map<String, dynamic>?;
    });
  }

  Future<void> _refresh() => _loadHomeData();

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = HomeStringsCatalog.of(lang);
    final auth = ref.watch(authControllerProvider);
    // Token-earned toast (audit §14) — listens for spinnerTokens increase via realtime/refresh
    ref.listen<int>(loyaltyProvider.select((s) => s.spinnerTokens), (prev, next) {
      if (prev != null && next > prev && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('${strings.tokenEarnedTitle} ${strings.tokenEarnedBody}'),
            action: SnackBarAction(label: strings.actionPlay, onPressed: () => context.push('/games/spinner')),
            duration: const Duration(seconds: 4),
          ));
      }
    });
    // Select only the fields this hub actually displays — avoids rebuilding
    // on spinnerTokens/matchTokens churn (audit #5).
    final tier = ref.watch(loyaltyProvider.select((s) => s.tier));
    final points = ref.watch(loyaltyProvider.select((s) => s.points));
    final stamps = ref.watch(loyaltyProvider.select((s) => s.stamps));
    final completedCards =
        ref.watch(loyaltyProvider.select((s) => s.completedCards));
    final sessionRole =
        ref.watch(sessionControllerProvider.select((s) => s.role));
    final signedIn = auth.phase == AuthPhase.ready;

    final googleName = auth.googleUser?.name.trim() ?? '';
    final firstName =
        signedIn && googleName.isNotEmpty ? googleName.split(' ').first : '';

    // Featured discovery — derived from paginated cache (PERF-04, no duplicate fetch)
    final featured = ref.watch(homeFeaturedProvider);

    final blocks = <Widget>[
      GreetingHeader(
        firstName: firstName,
        tier: tier,
        strings: strings,
        isGuest: !signedIn,
        onAvatarTap: () => context.go('/profile'),
      ),
    ];
    if (_activeOrders.isNotEmpty) {
      blocks.addAll([
        const SizedBox(height: AppSpacing.sm16),
        ActiveOrderStrip(
          orders: _activeOrders,
          strings: strings,
          onTap: () => context.push('/orders'),
        ),
      ]);
    }
    blocks.addAll([
      const SizedBox(height: AppSpacing.sm16),
      LoyaltyHeroCard(
        key: const Key('home_points_card'),
        points: signedIn ? points : 0,
        stamps: signedIn ? stamps : 0,
        completedCards: signedIn ? completedCards : 0,
        strings: strings,
        signedIn: signedIn,
      ),
      const SizedBox(height: AppSpacing.sm16),
      // Single primary action per screen — replaces the old equal-weight
      // "order now" tile (Starbucks fixed-signifier pattern).
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('home_order_cta'),
          onPressed: () => context.push('/mode-selection'),
          icon: const Icon(Icons.local_cafe, size: 20),
          label: Text(strings.actionOrderNow),
        ),
      ),
      const SizedBox(height: AppSpacing.sm16),
      QuickActionsRow(
        strings: strings,
        onComingSoon: () async {
          if (sessionRole == AppRole.staff) {
            context.push('/staff/lookup');
          } else {
            // Customer Scan & earn (FEATURES §3.2/§6) — mobile_scanner
            // sheet via QrScannerSheet + parseQrPhone; staff already routes
            // to /staff/lookup (#013).
            final raw = await showQrScannerSheet(context);
            if (!context.mounted) return;
            if (raw == null) return;
            final phone = parseQrPhone(raw);
            if (phone == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.comingSoon)),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.qrScanned(phone))),
              );
            }
          }
        },
      ),
    ]);
    if (featured.length >= 2) {
      blocks.addAll([
        const SizedBox(height: AppSpacing.md24),
        FeaturedCarousel(items: featured, strings: strings),
      ]);
    }
    if (_lastCompletedOrder != null) {
      blocks.addAll([
        const SizedBox(height: AppSpacing.md24),
        OrderAgainStrip(
          order: _lastCompletedOrder,
          strings: strings,
          onTap: () => context.push('/orders'),
        ),
      ]);
    }
    blocks.addAll([
      const SizedBox(height: AppSpacing.md24),
      // TODO(FEATURES §3.2 banner carousel): static 3-banner fallback
      // is intentional until the campaign feed lands; replace
      // strings.banners with a remote config / Supabase campaign
      // query when available.
      BannerCarousel(
        strings: strings,
        autoAdvance: kBannerAutoAdvance,
        onTapBanner: () => context.push('/games/quests'),
      ),
    ]);

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
            children: blocks,
          ),
        ),
      ),
    );
  }
}
