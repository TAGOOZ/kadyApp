// Spinner of Luck screen (#008 / FEATURES §5.1). Token-gated play through
// the shared loyalty seam (consumeSpinnerToken / grantPoints / grantVoucher /
// setDoubleNextOrder — never edited here). Result is pre-picked via the pure
// engine, then the wheel animates ~3s ease-out to land exactly on it.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_games.dart';
import '../../../core/l10n/strings_spinner.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/loyalty_controller.dart';
import '../../../domain/loyalty_gateway.dart';
import '../../../domain/spinner_engine.dart';
import 'widgets/result_modal.dart';
import 'widgets/spinner_wheel.dart';

class SpinnerScreen extends ConsumerStatefulWidget {
  const SpinnerScreen({super.key, this.rng});

  /// Injectable for deterministic tests; production uses a time-seeded RNG.
  final Random? rng;

  @override
  ConsumerState<SpinnerScreen> createState() => _SpinnerScreenState();
}

class _SpinnerScreenState extends ConsumerState<SpinnerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  late final Random _rng = widget.rng ?? Random();
  double _rotation = 0;
  bool _spinning = false;
  bool _claimingFree = false;

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  SpinPrize _prizeFromServer(String? raw) => switch (raw) {
        'points5' => SpinPrize.points5,
        'points10' => SpinPrize.points10,
        'toppingVoucher' => SpinPrize.toppingVoucher,
        'doubleNext' => SpinPrize.doubleNext,
        'drinkVoucher' => SpinPrize.drinkVoucher,
        'sold_out' => SpinPrize.nothing,
        _ => SpinPrize.nothing,
      };

  Future<void> _requestFreeToken() async {
    if (_claimingFree) return;
    setState(() => _claimingFree = true);
    final s = SpinnerStrings.of(ref.read(localeNotifierProvider));
    try {
      final res = await ref.read(loyaltyProvider.notifier).requestFreeToken();
      if (!mounted) return;
      final msg = res != null ? s.freeTokenSuccess : s.freeTokenRateLimited;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    } on FreeTokenRateLimitedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.freeTokenRateLimited)));
    } on TokenCapException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.freeTokenCapReached)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.freeTokenRateLimited)));
    } finally {
      if (mounted) setState(() => _claimingFree = false);
    }
  }

  Future<void> _spin() async {
    if (_spinning) return;
    final s = SpinnerStrings.of(ref.read(localeNotifierProvider));
    final loyalty = ref.read(loyaltyProvider.notifier);

    setState(() => _spinning = true);

    // Server-authoritative path when authenticated; fallback to local for offline/tests
    final isAuthed = ref.read(loyaltyGatewayProvider).currentUserId != null;
    late SpinPrize prize;

    if (isAuthed) {
      final res = await loyalty.playSpinnerGame();
      if (res == null) {
        if (!mounted) return;
        setState(() => _spinning = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.noTokenSnackbar)));
        return;
      }
      prize = _prizeFromServer(res['prize'] as String?);
    } else {
      final ok = await loyalty.consumeSpinnerToken();
      if (!ok) {
        if (!mounted) return;
        setState(() => _spinning = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(s.noTokenSnackbar)));
        return;
      }
      prize = roll(_rng);
    }

    final resolvedPrize = prize;
    final slice = sliceIndexFor(resolvedPrize, _rng);
    final target = spinTargetRotation(
      currentRotation: _rotation,
      sliceIndex: slice,
      extraTurns: 4 + _rng.nextInt(3), // 4..6 full turns
    );

    final anim = Tween<double>(begin: _rotation, end: target).animate(_curve);
    void onTick() => setState(() => _rotation = anim.value);
    _controller.addListener(onTick);

    try {
      await _controller.forward(from: 0).orCancel;
    } on TickerCanceled {
      _controller.removeListener(onTick);
      return;
    }
    _controller.removeListener(onTick);
    _rotation = target;

    if (!mounted) return;
    setState(() => _spinning = false);
    if (isAuthed) {
      // Server already granted prize atomically; just display
      ResultModal.show(
        context,
        prize: resolvedPrize,
        strings: s,
      );
    } else {
      ResultModal.showAndClaim(
        context,
        prize: resolvedPrize,
        strings: s,
        controller: ref.read(loyaltyProvider.notifier),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final s = SpinnerStrings.of(lang);
    final games = GamesStrings.of(lang);
    final tokens = ref.watch(loyaltyProvider.select((st) => st.spinnerTokens));
    final locked = tokens <= 0 && !_spinning;

    return Scaffold(
      appBar: AppBar(title: Text(s.screenTitle)),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.parchment.withValues(alpha: 0.55),
              AppColors.paperWhite,
              AppColors.background,
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.margin20),
          children: [
            Row(
              children: [
                Chip(label: Text(s.tokenChip(tokens))),
                const Spacer(),
                if (!_spinning && tokens > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.successContainer,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt,
                            size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          lang == AppLang.ar ? 'جاهز للف' : 'Ready',
                          style: AppTextStyles.labelMd.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md24),
            // Wheel wrapped in elevated paper card — removes empty-background feel.
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm16),
              decoration: BoxDecoration(
                color: AppColors.paperWhite,
                borderRadius: BorderRadius.circular(AppRadii.xl24),
                border: Border.all(
                    color: AppColors.outline.withValues(alpha: 0.10)),
                boxShadow: AppShadows.coffeeShadows(
                    blurRadius: 18, offset: const Offset(0, 8)),
              ),
              child: SpinnerWheel(
                rotationDeg: _rotation,
                onSpin: _spin,
                enabled: tokens > 0 && !_spinning,
                buttonLabel: s.spinButton,
              ),
            ),
            const SizedBox(height: AppSpacing.md24),
            // Prize legend — visual cues for each slice (fixes "lacks icons").
            _PrizeLegend(lang: lang),
            const SizedBox(height: AppSpacing.md24),
            if (locked)
              Card(
                key: const Key('spinner-locked-panel'),
                color: AppColors.paperWhite,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg16),
                  side: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_outline,
                            size: 28, color: AppColors.primary),
                      ),
                      const SizedBox(height: AppSpacing.sm16),
                      Text(s.lockedTitle,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.titleSm
                              .copyWith(color: AppColors.coffeeBean)),
                      const SizedBox(height: AppSpacing.xs8),
                      Text(games.spinnerLockedHint,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.textMuted)),
                      const SizedBox(height: AppSpacing.xs8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.parchment,
                          borderRadius:
                              BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(s.lockedFootnote,
                            style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: AppSpacing.sm16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _claimingFree ? null : _requestFreeToken,
                          icon: _claimingFree
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.card_giftcard, size: 18),
                          label: Text(s.freeTokenButton),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                color: AppColors.parchment,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg16),
                  side: BorderSide(
                      color: AppColors.outline.withValues(alpha: 0.10)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color:
                                AppColors.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.card_giftcard,
                            color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.sm16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(games.spinnerLockedHint,
                                style: AppTextStyles.titleSm.copyWith(
                                    color: AppColors.coffeeBean)),
                            const SizedBox(height: 4),
                            Text(s.lockedFootnote,
                                style: AppTextStyles.bodySm.copyWith(
                                    color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.info_outline,
                          size: 18, color: AppColors.outline),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm16),
            // Footnote — higher hierarchy than previous tiny centered Text.
            Text(
              lang == AppLang.ar
                  ? 'كل ٣ أختام = توكن جديد. الأختام من طلبات ≥ ٥٠ ج.'
                  : 'Every 3 stamps = 1 token. Stamps from orders ≥ 50 EGP.',
              textAlign: TextAlign.center,
              style: AppTextStyles.labelMd
                  .copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrizeLegend extends StatelessWidget {
  const _PrizeLegend({required this.lang});
  final AppLang lang;

  void _showTerms(BuildContext context) {
    final s = SpinnerStrings.of(lang);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.termsTitle),
        content: SingleChildScrollView(child: Text(s.termsBody, style: AppTextStyles.bodySm)),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.claimButton))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SpinnerStrings.of(lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              lang == AppLang.ar ? 'الجوائز المحتملة' : 'Possible prizes',
              style: AppTextStyles.titleSm
                  .copyWith(color: AppColors.coffeeBean),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showTerms(context),
              icon: const Icon(Icons.info_outline, size: 14),
              label: Text(s.termsButton, style: AppTextStyles.labelMd),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs8),
        Wrap(
          spacing: AppSpacing.xs8,
          runSpacing: AppSpacing.xs8,
          children: [
            for (final p in SpinPrize.values)
              _LegendChip(
                icon: p.icon,
                label: lang == AppLang.ar ? p.labelAr : p.labelEn,
                weight: p.weight.toInt(),
                isMuted: p == SpinPrize.nothing,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs8),
        Text(s.oddsFootnote,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelMd.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(s.expiryNote,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text(
          lang == AppLang.ar
              ? 'كل لفة لها جائزة — وحتى "حظ أوفر" بتقربك للتوكن الجاي.'
              : 'Every spin wins — even “Try again” keeps you close to the next token.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip(
      {required this.icon, required this.label, required this.weight, required this.isMuted});
  final IconData icon;
  final String label;
  final int weight;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMuted ? AppColors.parchment : AppColors.paperWhite,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
            color: AppColors.outline.withValues(alpha: 0.18)),
        boxShadow:
            AppShadows.coffeeShadows(blurRadius: 8, offset: const Offset(0, 3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16,
              color: isMuted ? AppColors.textMuted : AppColors.primary),
          const SizedBox(width: 6),
          Text('$label · $weight%',
              style: AppTextStyles.labelMd.copyWith(
                  color: isMuted
                      ? AppColors.textMuted
                      : AppColors.coffeeBean,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
