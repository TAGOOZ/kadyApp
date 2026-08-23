import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_games.dart';
import '../../../core/l10n/strings_scratch.dart';
import '../../../core/l10n/strings_spinner.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/games_prizes.dart';
import '../../../domain/loyalty_controller.dart';
import '../scratch/widgets/result_sheet.dart';

class SpinnerScreen extends ConsumerStatefulWidget {
  const SpinnerScreen({super.key, this.rng});

  /// Injectable for deterministic tests; production uses a time-seeded RNG.
  final Random? rng;

  @override
  ConsumerState<SpinnerScreen> createState() => _SpinnerScreenState();
}

class _SpinnerScreenState extends ConsumerState<SpinnerScreen> with SingleTickerProviderStateMixin {
  late final Random _rng = widget.rng ?? Random();
  AnimationController? _controller;
  double _angle = 0;
  GamePrize? _prize;
  bool _spinning = false;

  bool get _roundActive => _spinning || _prize != null;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _spin() async {
    if (_spinning) return;
    final loyalty = ref.read(loyaltyProvider.notifier);
    final ok = await loyalty.consumeSpinnerToken();
    if (!mounted) return;
    if (!ok) {
      final s = SpinnerStrings.of(ref.read(localeNotifierProvider));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.noTokenSnackbar)));
      return;
    }

    final prize = roll(_rng);
    setState(() {
      _prize = prize;
      _spinning = true;
    });

    const sweep = 2 * pi / 5;
    final prizeIndex = GamePrize.values.indexOf(prize);
    final prizeCenter = prizeIndex * sweep + sweep / 2;
    const pointerAngle = -pi / 2;

    var delta = pointerAngle - prizeCenter - _angle;
    delta %= 2 * pi;
    if (delta < 0) delta += 2 * pi;
    // small jitter keeps the landing inside the winning segment
    final jitter = (_rng.nextDouble() - 0.5) * sweep * 0.5;
    delta += jitter;
    // normalize jitter overflow back into the segment
    if (delta > 2 * pi) delta -= 2 * pi;
    if (delta < 0) delta += 2 * pi;

    const turns = 4;
    final target = _angle + turns * 2 * pi + delta;

    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final duration = disableAnimations ? Duration.zero : const Duration(milliseconds: 2800);

    _controller?.dispose();
    _controller = AnimationController(vsync: this, duration: duration);
    final curved = CurvedAnimation(parent: _controller!, curve: Curves.easeOutCubic);
    final animation = Tween<double>(begin: _angle, end: target).animate(curved);
    animation.addListener(() {
      if (mounted) setState(() => _angle = animation.value);
    });
    await _controller!.forward();
    if (!mounted) return;
    setState(() {
      _spinning = false;
      _angle = target;
    });
    _showResult();
  }

  void _showResult() {
    final lang = ref.read(localeNotifierProvider);
    final s = SpinnerStrings.of(lang);
    final prize = _prize ?? GamePrize.nothing;

    ResultSheet.showAndClaim(
      context,
      win: prize != GamePrize.nothing,
      icon: prize.icon,
      labelAr: prize.labelAr,
      winTitle: s.resultWinTitle,
      nothingTitle: s.resultNothingTitle,
      claimButton: s.claimButton,
      validChip: prize.isVoucher ? ScratchStrings.of(lang).validChip : null,
      voucherHint: prize.isVoucher ? ScratchStrings.of(lang).voucherHint : null,
      claim: () => creditGamePrize(ref.read(loyaltyProvider.notifier), prize),
    ).then((_) {
      if (!mounted) return;
      setState(() => _prize = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final s = SpinnerStrings.of(lang);
    final games = GamesStrings.of(lang);
    final tokens = ref.watch(loyaltyProvider.select((st) => st.spinnerTokens));
    final locked = tokens <= 0 && !_roundActive;

    return Scaffold(
      appBar: AppBar(title: Text(s.screenTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.margin20),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Chip(
              key: const Key('spinner-token-chip'),
              label: Text('${s.tokenChipPrefix}: $tokens'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          if (locked)
            Card(
              key: const Key('spinner-locked-panel'),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md24),
                child: Column(
                  children: [
                    const Icon(Icons.lock_outline, size: 40, color: AppColors.outline),
                    const SizedBox(height: AppSpacing.xs8),
                    Text(s.lockedTitle, style: AppTextStyles.titleMd, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.xs8),
                    Text(games.spinnerLockedHint,
                        style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          else ...[
            Center(
              child: SizedBox(
                width: 280,
                height: 308,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      top: 28,
                      child: CustomPaint(
                        key: const ValueKey('spinner-wheel'),
                        painter: _WheelPainter(angle: _angle),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      child: CustomPaint(
                        size: const Size(28, 22),
                        painter: _PointerPainter(color: AppColors.primary),
                      ),
                    ),
                    Positioned.fill(
                      top: 28,
                      child: Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.paperWhite,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.outline.withValues(alpha: 0.2)),
                            boxShadow: AppShadows.coffeeShadows(blurRadius: 10, offset: const Offset(0, 4)),
                          ),
                          child: const Icon(Icons.casino, color: AppColors.primary, size: 28),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm16),
            Text(
              s.roundHint,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('spinner-spin-button'),
                onPressed: _spinning ? null : _spin,
                child: Text(_spinning ? s.spinningLabel : s.spinButton),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg32),
          Card(
            key: const Key('spinner-legend'),
            color: AppColors.parchment,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.legendTitle, style: AppTextStyles.titleSm),
                  const SizedBox(height: AppSpacing.xs8),
                  Wrap(
                    spacing: AppSpacing.xs8,
                    runSpacing: AppSpacing.xs8,
                    children: [
                      for (final prize in GamePrize.values)
                        Chip(
                          key: ValueKey('spinner-legend-${prize.name}'),
                          avatar: Icon(prize.icon, size: 18, color: AppColors.primary),
                          label: Text(prize.labelAr, style: AppTextStyles.bodySm),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.angle});

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 4;
    const sweep = 2 * pi / 5;
    final fills = <Color>[
      AppColors.primaryFixedTint,
      AppColors.parchment,
      AppColors.paperWhite,
      AppColors.secondaryContainer.withValues(alpha: 0.22),
      AppColors.primary.withValues(alpha: 0.08),
    ];

    for (var i = 0; i < 5; i++) {
      final start = angle + i * sweep;
      final fill = Paint()
        ..color = fills[i]
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        fill,
      );
      final stroke = Paint()
        ..color = AppColors.outline.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        stroke,
      );
      final edgeEnd = center + Offset(cos(start), sin(start)) * radius;
      canvas.drawLine(center, edgeEnd, stroke);
    }

    final rim = Paint()
      ..color = AppColors.outline.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, rim);

    final textStyle = AppTextStyles.bodySm.copyWith(
      color: AppColors.coffeeBean,
      fontWeight: FontWeight.w600,
      fontSize: 11,
      height: 1.2,
    );
    for (var i = 0; i < 5; i++) {
      final mid = angle + i * sweep + sweep / 2;
      final labelPos = center + Offset(cos(mid), sin(mid)) * radius * 0.62;
      final prize = GamePrize.values[i];
      final tp = TextPainter(
        text: TextSpan(text: prize.labelAr, style: textStyle),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: radius * 0.58);
      tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.angle != angle;
}

class _PointerPainter extends CustomPainter {
  _PointerPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, shadow);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) => old.color != color;
}
