// SpinnerWheel (#008): custom-painted 6-slice wheel + fixed top pointer +
// orange center hub button. Pure presentation — rotation is driven by the
// screen's AnimationController; slice layout comes from kSpinnerSlices.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/spinner_engine.dart';

class SpinnerWheel extends StatelessWidget {
  const SpinnerWheel({
    super.key,
    required this.rotationDeg,
    required this.onSpin,
    required this.enabled,
    required this.buttonLabel,
  });

  /// Current absolute wheel rotation in degrees (clockwise-positive).
  final double rotationDeg;
  final VoidCallback onSpin;
  final bool enabled;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(double.infinity, double.infinity),
            painter: _SpinnerWheelPainter(rotationRad(rotationDeg)),
          ),
          // Center hub: orange circular spin button, disabled while spinning.
          SizedBox(
            width: 84,
            height: 84,
            child: FilledButton(
              onPressed: enabled ? onSpin : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondaryContainer,
                disabledBackgroundColor:
                    AppColors.secondaryContainer.withValues(alpha: 0.45),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                shape: const CircleBorder(),
                textStyle: AppTextStyles.titleMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

double rotationRad(double deg) => deg * math.pi / 180;

/// Alternating deep-forest / parchment slices with orange separators and rim,
/// labels laid along each slice bisector; pointer triangle pinned at top.
class _SpinnerWheelPainter extends CustomPainter {
  const _SpinnerWheelPainter(this.rotation);

  final double rotation;

  static const _hubRadius = 46.0;
  static const _pointerSize = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - _pointerSize - 4;

    // Fixed pointer at 12 o'clock (drawn before rotating the wheel).
    _paintPointer(canvas, center, radius);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final sweep = 2 * math.pi / kSpinnerSliceCount;
    final start = -math.pi / 2; // first slice starts at 12 o'clock

    for (var i = 0; i < kSpinnerSliceCount; i++) {
      final from = start + i * sweep;
      final paint = Paint()
        ..color = i.isEven ? AppColors.primary : AppColors.parchment
        ..style = PaintingStyle.fill;
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: radius),
          from, sweep, true, paint);
    }

    // Orange separators along every boundary.
    final sep = Paint()
      ..color = AppColors.secondaryContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < kSpinnerSliceCount; i++) {
      final a = start + i * sweep;
      canvas.drawLine(
        Offset(math.cos(a), math.sin(a)) * _hubRadius,
        Offset(math.cos(a), math.sin(a)) * radius,
        sep,
      );
    }

    // Orange rim.
    canvas.drawCircle(Offset.zero, radius, sep..strokeWidth = 4);

    _paintLabels(canvas, radius);
    canvas.restore();

    // Hub disc behind the button widget.
    canvas.drawCircle(
      center,
      _hubRadius - 6,
      Paint()..color = AppColors.coffeeBean,
    );
  }

  void _paintPointer(Canvas canvas, Offset center, double radius) {
    final tip =
        Offset(center.dx, center.dy - radius + _pointerSize * 0.35);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - _pointerSize * 0.7,
          tip.dy - _pointerSize * 1.5)
      ..lineTo(tip.dx + _pointerSize * 0.7,
          tip.dy - _pointerSize * 1.5)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.secondaryContainer);
    canvas.drawPath(path, Paint()
      ..color = AppColors.coffeeBean
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  void _paintLabels(Canvas canvas, double radius) {
    final sweep = 360 / kSpinnerSliceCount;
    for (var i = 0; i < kSpinnerSliceCount; i++) {
      final prize = kSpinnerSlices[i];
      final midDeg = i * sweep + sweep / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: prize.labelAr,
          style: AppTextStyles.labelMd.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: i.isEven ? AppColors.paperWhite : AppColors.coffeeBean,
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * 0.62);

      canvas.save();
      canvas.rotate(rotationRad(midDeg));
      // Draw along the radial axis, just past the hub, centered on it.
      tp.paint(canvas, Offset(_hubRadius + (radius - _hubRadius) * 0.42,
          -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SpinnerWheelPainter old) =>
      old.rotation != rotation;
}
