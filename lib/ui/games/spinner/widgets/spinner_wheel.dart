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
          // Center hub: tactile orange CTA with white ring + coffee shadow.
          // Spec: AppColors only, no raw hex. Shadow from AppShadows ledger.
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: AppShadows.coffeeShadows(
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ),
            child: SizedBox(
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
                  elevation: enabled ? 6 : 0,
                  shadowColor:
                      AppColors.coffeeBean.withValues(alpha: 0.35),
                  padding: EdgeInsets.zero,
                  textStyle: AppTextStyles.titleMd.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
                child: Text(buttonLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double rotationRad(double deg) => deg * math.pi / 180;

/// Alternating deep-forest / parchment slices with orange separators and rim,
/// labels centered inside each slice (not on dividers), kept upright
/// horizontal for Arabic readability, with per-slice icon + text.
/// Pointer triangle pinned at top with shadow and exact rim alignment.
class _SpinnerWheelPainter extends CustomPainter {
  const _SpinnerWheelPainter(this.rotation);

  final double rotation;

  static const _hubRadius = 46.0;
  static const _pointerSize = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - _pointerSize - 4;

    // Soft wheel drop shadow (coffee-tinted, per DESIGN.md).
    canvas.drawCircle(
      center.translate(0, 4),
      radius,
      Paint()
        ..color = const Color(0x1A4B2C20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

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
      canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: radius),
          from,
          sweep,
          true,
          paint);
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

    // Polished double rim: white outer hairline + orange inner for lift.
    canvas.drawCircle(
        Offset.zero,
        radius + 1.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    canvas.drawCircle(Offset.zero, radius, sep..strokeWidth = 4);

    _paintLabels(canvas, radius, start, sweep);
    canvas.restore();

    // Hub disc behind the button widget — coffee-bean with white ring.
    canvas.drawCircle(
      center.translate(0, 2),
      _hubRadius - 6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      center,
      _hubRadius - 6,
      Paint()..color = AppColors.coffeeBean,
    );
    canvas.drawCircle(
      center,
      _hubRadius - 6,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintPointer(Canvas canvas, Offset center, double radius) {
    // Tip sits exactly on the rim (no gap), base floats above.
    final tip = Offset(center.dx, center.dy - radius);
    final baseY = tip.dy - _pointerSize * 1.35;
    final halfW = _pointerSize * 0.78;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - halfW, baseY)
      ..lineTo(tip.dx + halfW, baseY)
      ..close();

    // Shadow behind pointer for depth.
    final shadowPath = path.shift(const Offset(0, 2.5));
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawPath(path, Paint()..color = AppColors.secondaryContainer);
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.coffeeBean
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    // Small white highlight stroke on top edge for polish.
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - halfW * 0.85, baseY + 1)
        ..lineTo(tip.dx, tip.dy + 1)
        ..lineTo(tip.dx + halfW * 0.85, baseY + 1),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintLabels(
      Canvas canvas, double radius, double start, double sweep) {
    // Distance from center to label group (icon + text) — mid-radius.
    final labelRadius = _hubRadius + (radius - _hubRadius) * 0.58;

    for (var i = 0; i < kSpinnerSliceCount; i++) {
      final prize = kSpinnerSlices[i];
      final midAngle = start + i * sweep + sweep / 2;
      final pos = Offset(math.cos(midAngle), math.sin(midAngle)) * labelRadius;

      final isDark = i.isEven;
      final textColor = isDark ? AppColors.paperWhite : AppColors.coffeeBean;
      final iconColor = isDark ? AppColors.paperWhite : AppColors.primary;

      // Icon painter — MaterialIcons glyph via codePoint.
      final iconChar = String.fromCharCode(prize.icon.codePoint);
      final iconPainter = TextPainter(
        text: TextSpan(
          text: iconChar,
          style: TextStyle(
            fontFamily: prize.icon.fontFamily,
            package: prize.icon.fontPackage,
            fontSize: 22,
            height: 1,
            color: iconColor,
            shadows: isDark
                ? const [
                    Shadow(
                        color: Color(0x66000000),
                        blurRadius: 3,
                        offset: Offset(0, 1)),
                  ]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      final tp = TextPainter(
        text: TextSpan(
          text: prize.labelAr,
          style: AppTextStyles.labelMd.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.15,
            fontSize: 12.5,
            color: textColor,
            shadows: isDark
                ? const [
                    Shadow(
                        color: Color(0x66000000),
                        blurRadius: 3,
                        offset: Offset(0, 1)),
                  ]
                : null,
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
      )..layout(maxWidth: radius * 0.68);

      final gap = 3.0;
      final groupH = iconPainter.height + gap + tp.height;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      // Keep group upright (horizontal) regardless of wheel rotation —
      // counter-rotate the wheel's rotation so Arabic stays readable.
      canvas.rotate(-rotation);
      iconPainter.paint(
          canvas, Offset(-iconPainter.width / 2, -groupH / 2));
      tp.paint(
          canvas,
          Offset(
              -tp.width / 2, -groupH / 2 + iconPainter.height + gap));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SpinnerWheelPainter old) =>
      old.rotation != rotation;
}
