// Campaign banner carousel (#005): 3 deep-ember gradient cards,
// auto-advances every 5s (paused under reduce-motion), stops while the
// pointer is down, tap → quests.
// TODO(FEATURES §3.2): static 3-banner list is intentional fallback until
// the campaign feed lands; replace strings.banners with a remote campaign
// config / Supabase query when available.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';

/// Pure carousel math — extracted for unit tests: wraps forward and guards
/// degenerate counts.
int nextBannerIndex({required int current, required int count}) {
  if (count <= 0) return 0;
  return (current + 1) % count;
}

const Duration kBannerAutoAdvance = Duration(seconds: 5);

class BannerCarousel extends StatefulWidget {
  const BannerCarousel({
    super.key,
    required this.strings,
    required this.onTapBanner,
    this.autoAdvance = kBannerAutoAdvance,
  });

  final HomeStrings strings;
  final VoidCallback onTapBanner;

  /// Exposed so widget tests can pin/shorten the cadence.
  final Duration autoAdvance;

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  /// Derived from MediaQuery in [didChangeDependencies]; every timer start
  /// path checks it so a pointer interaction can never resurrect
  /// auto-advance for reduce-motion customers.
  bool _autoAdvanceEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.88);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced-motion customers get a static first banner: no timer, no
    // auto-advance animation.
    _autoAdvanceEnabled = !MediaQuery.of(context).disableAnimations;
    if (!_autoAdvanceEnabled) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null || !_timer!.isActive) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (!_autoAdvanceEnabled) return;
    _timer?.cancel();
    _timer = Timer.periodic(widget.autoAdvance, (_) {
      if (!_controller.hasClients) return;
      final target = nextBannerIndex(
        current: _index,
        count: widget.strings.banners.length,
      );
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onPageChanged(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final banners = widget.strings.banners;
    return Column(
      children: [
        Listener(
          onPointerDown: (_) => _timer?.cancel(),
          onPointerUp: (_) => _startTimer(),
          onPointerCancel: (_) => _startTimer(),
          child: SizedBox(
            height: 116,
            child: PageView.builder(
              controller: _controller,
              itemCount: banners.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final (title, body) = banners[index];
                return _BannerCard(
                  key: ValueKey('home_banner_$index'),
                  title: title,
                  body: body,
                  gradient: _gradientFor(index),
                  onTap: () {
                    setState(() => _index = index);
                    widget.onTapBanner();
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs8),
        HomeDotsIndicator(count: banners.length, activeIndex: _index),
      ],
    );
  }

  // Deep-ember orange ramps per #005 spec — every stop holds white text at
  // ≥4.5:1 (the original bright stops FF7434/FFB27A measured 2.7:1/1.8:1).
  static LinearGradient _gradientFor(int index) => switch (index % 3) {
        0 => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.bannerEmber, AppColors.bannerEmberDark],
          ),
        1 => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.bannerEmberMid, AppColors.bannerEmberMidDark],
          ),
        _ => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.bannerEmber, AppColors.bannerEmberAltDark],
          ),
      };
}

/// Dots row mirroring the current page; also unit-testable in isolation.
class HomeDotsIndicator extends StatelessWidget {
  const HomeDotsIndicator({
    super.key,
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('home_banner_dots'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == activeIndex;
        return Container(
          key: ValueKey('home_banner_dot_$index'),
          width: active ? 18 : 7,
          height: 7,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: active ? AppColors.secondary : AppColors.outline
                .withValues(alpha: 0.35),
            borderRadius:
                const BorderRadius.all(Radius.circular(AppRadii.pill)),
          ),
        );
      }),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    super.key,
    required this.title,
    required this.body,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String body;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xl24)),
          boxShadow: AppShadows.coffeeShadows(offset: const Offset(0, 4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.titleMd.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: AppTextStyles.bodyLg.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
