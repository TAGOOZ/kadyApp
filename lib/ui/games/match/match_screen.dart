// 3-Card Match screen (#009 / FEATURES §5.2). Token-gated play through the
// shared loyalty seam (consumeMatchToken / grantPoints / grantVoucher — never
// edited here). The pure engine pre-picks a round outcome (two-match 60% ·
// three-match 10% · none 30%) and arranges three face symbols to realize it;
// taps then reveal the cards sequentially (~300ms flip each).
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_games.dart';
import '../../../core/l10n/strings_match.dart';
import '../../../core/l10n/strings_scratch.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/games_prizes.dart';
import '../../../domain/loyalty_controller.dart';
import '../scratch/widgets/result_sheet.dart';
import 'widgets/match_card.dart';

/// Round outcomes tuned small-win-heavy (#009): twoMatch 60% · threeMatch
/// 10% · none 30%.
enum MatchOutcome { twoMatch, threeMatch, none }

extension MatchOutcomeX on MatchOutcome {
  /// Relative probability weight (sums to 100).
  double get weight => switch (this) {
        MatchOutcome.twoMatch => 60,
        MatchOutcome.threeMatch => 10,
        MatchOutcome.none => 30,
      };

  /// Reward vocabulary shared with the scratch pool (games_prizes.dart).
  GamePrize get prize => switch (this) {
        MatchOutcome.twoMatch => GamePrize.pts5,
        MatchOutcome.threeMatch => GamePrize.drinkVoucher,
        MatchOutcome.none => GamePrize.nothing,
      };
}

/// Themed symbol pair printed on a card face.
class MatchFace {
  const MatchFace({required this.icon, required this.labelAr});
  final IconData icon;
  final String labelAr;
}

/// Symbol pool: فنجان ☕ / حبة قهوة / لوجو القاضي.
const List<MatchFace> kMatchFaces = [
  MatchFace(icon: Icons.local_cafe, labelAr: 'فنجان ☕'),
  MatchFace(icon: Icons.grain, labelAr: 'حبة قهوة'),
  MatchFace(icon: Icons.workspace_premium, labelAr: 'لوجو القاضي'),
];

const int kMatchCardCount = 3;

/// Pure match engine — no state, no IO. Outcome is always pre-computed, then
/// the three card faces are arranged to realize it.
abstract final class MatchRound {
  /// Weighted pick over outcomes; `r.nextDouble() * totalWeight` walk.
  static MatchOutcome pick(Random r) {
    final total =
        MatchOutcome.values.fold<double>(0, (s, o) => s + o.weight);
    var t = r.nextDouble() * total;
    for (final outcome in MatchOutcome.values) {
      t -= outcome.weight;
      if (t < 0) return outcome;
    }
    return MatchOutcome.values.last;
  }

  /// Pool indices (into [kMatchFaces]) for the three cards realizing
  /// [outcome]: exactly two equal for twoMatch, all equal for threeMatch,
  /// all distinct for none.
  static List<int> arrangeFaces(MatchOutcome outcome, Random r) {
    switch (outcome) {
      case MatchOutcome.threeMatch:
        return List.filled(kMatchCardCount, r.nextInt(kMatchFaces.length));
      case MatchOutcome.twoMatch:
        final winner = r.nextInt(kMatchFaces.length);
        final others =
            List.generate(kMatchFaces.length, (i) => i)..remove(winner);
        final loser = others[r.nextInt(others.length)];
        return _shuffled([winner, winner, loser], r);
      case MatchOutcome.none:
        return _shuffled(List.generate(kMatchFaces.length, (i) => i), r);
    }
  }

  static List<int> _shuffled(List<int> items, Random r) {
    final copy = [...items];
    for (var i = copy.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final tmp = copy[i];
      copy[i] = copy[j];
      copy[j] = tmp;
    }
    return copy;
  }

  /// Runs [n] seeded picks and counts outcomes — used by tests to assert the
  /// distribution tracks the weights within tolerance.
  static Map<MatchOutcome, int> simulate(int n, Random r) {
    final counts = {for (final o in MatchOutcome.values) o: 0};
    for (var i = 0; i < n; i++) {
      final outcome = pick(r);
      counts[outcome] = counts[outcome]! + 1;
    }
    return counts;
  }
}

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key, this.rng});

  /// Injectable for deterministic tests; production uses a time-seeded RNG.
  final Random? rng;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  late final Random _rng = widget.rng ?? Random();

  MatchOutcome? _outcome;
  List<int>? _faces;
  final List<bool> _revealed = List.filled(kMatchCardCount, false);
  int _flips = 0;
  bool _starting = false;

  bool get _roundActive => _faces != null;

  Future<void> _onCardTap(int index) async {
    if (_starting || _revealed[index]) return;
    final loyalty = ref.read(loyaltyProvider.notifier);

    if (!_roundActive) {
      // Round start: one matchToken buys the whole three-card session.
      setState(() => _starting = true);
      final ok = await loyalty.consumeMatchToken();
      if (!mounted) return;
      if (!ok) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(MatchStrings.of(ref.read(localeNotifierProvider)).noTokenSnackbar)));
        return;
      }
      final outcome = MatchRound.pick(_rng);
      setState(() {
        _outcome = outcome;
        _faces = MatchRound.arrangeFaces(outcome, _rng);
        _flips = 0;
        _starting = false;
      });
    }

    // Sequential reveal on taps; the cosmetic attempts counter ticks down
    // once the flip lands (~340ms), so it reads ٣ exactly at round start.
    setState(() => _revealed[index] = true);
    await Future<void>.delayed(const Duration(milliseconds: 340));
    if (!mounted || !_roundActive) return;
    setState(() => _flips++);
    if (_flips >= kMatchCardCount) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      _showResult();
    }
  }

  void _showResult() {
    final lang = ref.read(localeNotifierProvider);
    final s = MatchStrings.of(lang);
    final outcome = _outcome ?? MatchOutcome.none;
    final prize = outcome.prize;

    ResultSheet.showAndClaim(
      context,
      win: outcome != MatchOutcome.none,
      icon: prize.icon,
      labelAr: switch (outcome) {
        MatchOutcome.twoMatch => s.twoMatchLabel,
        MatchOutcome.threeMatch => s.threeMatchLabel,
        MatchOutcome.none => prize.labelAr,
      },
      winTitle: s.resultWinTitle,
      nothingTitle: s.resultNothingTitle,
      claimButton: s.claimButton,
      validChip: prize.isVoucher ? ScratchStrings.of(lang).validChip : null,
      voucherHint:
          prize.isVoucher ? ScratchStrings.of(lang).voucherHint : null,
      claim: () =>
          creditGamePrize(ref.read(loyaltyProvider.notifier), prize),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        _outcome = null;
        _faces = null;
        for (var i = 0; i < kMatchCardCount; i++) {
          _revealed[i] = false;
        }
        _flips = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final s = MatchStrings.of(lang);
    final games = GamesStrings.of(lang);
    final tokens = ref.watch(loyaltyProvider.select((st) => st.matchTokens));
    final locked = tokens <= 0 && !_roundActive;

    return Scaffold(
      appBar: AppBar(title: Text(s.screenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.margin20),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _roundActive
                ? Chip(
                    key: const Key('match-attempts-chip'),
                    label: Text(s.attempts(kMatchCardCount - _flips)),
                  )
                : Chip(
                    key: const Key('match-token-chip'),
                    label: Text('${s.tokenChipPrefix}: $tokens'),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          Row(
            children: [
              for (var i = 0; i < kMatchCardCount; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm16),
                Expanded(
                  child: MatchCard(
                    key: ValueKey('match-card-$i'),
                    icon: kMatchFaces[_faces != null
                            ? _faces![i]
                            : i % kMatchFaces.length]
                        .icon,
                    label: kMatchFaces[_faces != null
                            ? _faces![i]
                            : i % kMatchFaces.length]
                        .labelAr,
                    revealed: _revealed[i],
                    enabled: !locked && !_starting,
                    onTap: () => _onCardTap(i),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm16),
          Card(
            key: const Key('match-legend'),
            color: AppColors.parchment,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm16),
              child: Column(
                children: [
                  Text(s.legendTwo, style: AppTextStyles.bodySm),
                  const SizedBox(height: AppSpacing.xs8),
                  Text(
                    s.legendThree,
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.secondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          if (locked)
            Card(
              key: const Key('match-locked-panel'),
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
                    Text(games.matchLockedHint,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.outline)),
                    Text(s.lockedFootnote,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.secondary)),
                  ],
                ),
              ),
            )
          else
            Text(
              s.roundHint,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.outline),
            ),
        ],
      ),
    );
  }
}
