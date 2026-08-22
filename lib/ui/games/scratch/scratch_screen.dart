// Scratch & Win screen (#009 / FEATURES §5.3). Token-gated play through the
// shared loyalty seam (consumeScratchToken — never edited here). The prize is
// pre-picked from the shared weighted pool (games_prizes.dart) at round
// start; the coating auto-completes at ≥55% scratched and the reward is
// credited on استلم المكافأة. Campaign badge reads the public campaigns table
// (hidden offline).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_games.dart';
import '../../../core/l10n/strings_scratch.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/games_prizes.dart';
import '../../../domain/loyalty_controller.dart';
import 'widgets/result_sheet.dart';
import 'widgets/scratch_surface.dart';

class ScratchScreen extends ConsumerStatefulWidget {
  const ScratchScreen({super.key, this.rng});

  /// Injectable for deterministic tests; production uses a time-seeded RNG.
  final Random? rng;

  @override
  ConsumerState<ScratchScreen> createState() => _ScratchScreenState();
}

class _ScratchScreenState extends ConsumerState<ScratchScreen> {
  GamePrize? _prize;
  bool _revealed = false;
  bool _roundActive = false;
  bool _starting = false;
  int _session = 0;
  bool _campaignActive = false;

  @override
  void initState() {
    super.initState();
    _loadCampaign();
  }

  /// Public read of the campaigns table; hidden when offline / RLS-blocked.
  Future<void> _loadCampaign() async {
    try {
      final rows = await supabase
          .from('campaigns')
          .select('id')
          .eq('kind', 'match_night')
          .eq('active', true)
          .limit(1);
      if (!mounted) return;
      setState(() => _campaignActive = (rows as List).isNotEmpty);
    } catch (_) {
      // Offline policy: campaign badge stays hidden.
    }
  }

  Future<void> _ensureRound() async {
    if (_roundActive || _starting) return;
    final s = ScratchStrings.of(ref.read(localeNotifierProvider));
    final loyalty = ref.read(loyaltyProvider.notifier);

    setState(() => _starting = true);
    final ok = await loyalty.consumeScratchToken();
    if (!mounted) return;
    if (!ok) {
      setState(() => _starting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.noTokenSnackbar)));
      return;
    }
    setState(() {
      _prize = roll(widget.rng ?? Random());
      _roundActive = true;
      _starting = false;
    });
  }

  void _claim() {
    final lang = ref.read(localeNotifierProvider);
    final s = ScratchStrings.of(lang);
    final prize = _prize ?? GamePrize.nothing;

    ResultSheet.showAndClaim(
      context,
      win: prize != GamePrize.nothing,
      icon: prize.icon,
      labelAr: prize.labelAr,
      winTitle: s.resultWinTitle,
      nothingTitle: s.resultNothingTitle,
      claimButton: s.claimButton,
      validChip: prize.isVoucher ? s.validChip : null,
      voucherHint: prize.isVoucher ? s.voucherHint : null,
      claim: () => creditGamePrize(ref.read(loyaltyProvider.notifier), prize),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        _prize = null;
        _revealed = false;
        _roundActive = false;
        _session++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final s = ScratchStrings.of(lang);
    final games = GamesStrings.of(lang);
    final tokens = ref.watch(loyaltyProvider.select((st) => st.scratchTokens));
    final locked = tokens <= 0 && !_roundActive;

    return Scaffold(
      appBar: AppBar(title: Text(s.screenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.margin20),
        children: [
          if (_campaignActive)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Chip(
                key: const Key('scratch-campaign-chip'),
                label: Text(s.campaignChip),
                visualDensity: VisualDensity.compact,
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Chip(
              key: const Key('scratch-token-chip'),
              label: Text('${s.tokenChipPrefix}: $tokens'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          if (!locked) ...[
            AspectRatio(
              aspectRatio: 1.45,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.xl24),
                  child: ScratchSurface(
                    key: ValueKey('scratch-surface-$_session'),
                    onReveal: () => setState(() => _revealed = true),
                    onScratchStart: _ensureRound,
                    enabled: !_starting,
                    child: _PrizeLayer(prize: _prize, strings: s),
                  ),
                ),
            ),
            const SizedBox(height: AppSpacing.sm16),
            Text(
              s.scratchHint,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.outline),
            ),
            const SizedBox(height: AppSpacing.sm16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('scratch-claim-button'),
                    onPressed: _revealed ? _claim : null,
                    child: Text(s.claimButton),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm16),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(s.laterButton),
                ),
              ],
            ),
          ] else
            Card(
              key: const Key('scratch-locked-panel'),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md24),
                child: Column(
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 40, color: AppColors.outline),
                    const SizedBox(height: AppSpacing.xs8),
                    Text(s.lockedTitle, style: AppTextStyles.titleMd),
                    const SizedBox(height: AppSpacing.xs8),
                    // Locked hint comes from the shared games catalog.
                    Text(games.scratchLockedHint,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.outline)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg32),
          // Upcoming scratch cards — locked placeholders.
          Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm16),
                Expanded(
                  child: Container(
                    key: Key('scratch-upcoming-$i'),
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.parchment.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppRadii.mdLg12),
                      border: Border.all(color: AppColors.outline.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline, color: AppColors.outline),
                        const SizedBox(height: AppSpacing.xs8),
                        Text(
                          s.upcomingCaption,
                          style:
                              AppTextStyles.bodySm.copyWith(color: AppColors.outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Prize layer revealed under the coating: green tint + big icon + Arabic
/// label; voucher prizes carry a صالحة chip with usage hint.
class _PrizeLayer extends StatelessWidget {
  const _PrizeLayer({required this.prize, required this.strings});

  final GamePrize? prize;
  final ScratchStrings strings;

  @override
  Widget build(BuildContext context) {
    final p = prize;
    return Container(
      color: AppColors.primaryFixedTint,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.md24),
      child: p == null
          ? Icon(Icons.card_giftcard, size: 56, color: AppColors.primary)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(p.icon, size: 64, color: AppColors.primary),
                const SizedBox(height: AppSpacing.xs8),
                Text(
                  p.labelAr,
                  style: AppTextStyles.headlineMobile.copyWith(color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
                if (p.isVoucher) ...[
                  const SizedBox(height: AppSpacing.xs8),
                  Wrap(
                    spacing: AppSpacing.xs8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(strings.validChip),
                        visualDensity: VisualDensity.compact,
                      ),
                      Text(
                        strings.voucherHint,
                        style: AppTextStyles.bodySm.copyWith(color: AppColors.outline),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
