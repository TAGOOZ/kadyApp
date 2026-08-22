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

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_spinning) return;
    final s = SpinnerStrings.of(ref.read(localeNotifierProvider));
    final loyalty = ref.read(loyaltyProvider.notifier);

    setState(() => _spinning = true);
    final ok = await loyalty.consumeSpinnerToken();
    if (!ok) {
      if (!mounted) return;
      setState(() => _spinning = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.noTokenSnackbar)));
      return;
    }

    // Pre-compute the outcome, then animate exactly onto its slice.
    final prize = roll(_rng);
    final slice = sliceIndexFor(prize, _rng);
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
    ResultModal.showAndClaim(
      context,
      prize: prize,
      strings: s,
      controller: ref.read(loyaltyProvider.notifier),
    );
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
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.margin20),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Chip(label: Text(s.tokenChip(tokens))),
          ),
          const SizedBox(height: AppSpacing.sm16),
          SpinnerWheel(
            rotationDeg: _rotation,
            onSpin: _spin,
            enabled: tokens > 0 && !_spinning,
            buttonLabel: s.spinButton,
          ),
          const SizedBox(height: AppSpacing.sm16),
          if (locked)
            Card(
              key: const Key('spinner-locked-panel'),
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
                    Text(games.spinnerLockedHint,
                        style:
                            AppTextStyles.bodySm.copyWith(color: AppColors.outline)),
                    Text(s.lockedFootnote,
                        style:
                            AppTextStyles.bodySm.copyWith(color: AppColors.secondary)),
                  ],
                ),
              ),
            )
          else
            Text(
              games.spinnerLockedHint,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.outline),
            ),
        ],
      ),
    );
  }
}
