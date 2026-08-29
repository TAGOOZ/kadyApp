// MatchCard (#009): one of the three face-down cards. Dark-green back with a
// gold triangle pattern (CustomPainter); tap flips to the symbol face via an
// AnimatedSwitcher rotateY transition (~300ms).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.icon,
    required this.label,
    required this.revealed,
    required this.onTap,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final bool revealed;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled && !revealed ? onTap : null,
      child: AspectRatio(
        aspectRatio: 0.78,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            // Entering children swing in from -90°, leaving ones out to 90° —
            // reads as a card flip around the vertical axis.
            final entering = child.key == ValueKey(revealed);
            final angle = (entering ? -1 : 1) * (1 - animation.value) * math.pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(angle),
              child: child,
            );
          },
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: [...previousChildren, ?currentChild],
          ),
          child: revealed
              ? _FaceFront(key: ValueKey(revealed), icon: icon, label: label)
              : const _FaceBack(key: ValueKey(false)),
        ),
      ),
    );
  }
}

class _FaceFront extends StatelessWidget {
  const _FaceFront({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Shadow only — pairing the hairline border with a soft wide shadow
      // reads as a ghost card.
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius: BorderRadius.circular(AppRadii.mdLg12),
        boxShadow: AppShadows.coffeeShadows(),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: AppColors.primary),
          const SizedBox(height: AppSpacing.xs8),
          Text(
            label,
            style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _FaceBack extends StatelessWidget {
  const _FaceBack({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.mdLg12),
        boxShadow: AppShadows.coffeeShadows(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.mdLg12),
        child: const CustomPaint(
          size: Size(double.infinity, double.infinity),
          painter: _CardBackPainter(),
        ),
      ),
    );
  }
}

/// Dark-green back with a repeating gold triangle pattern.
class _CardBackPainter extends CustomPainter {
  const _CardBackPainter();

  static const _gold = AppColors.cardGold;
  static const _cell = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = Paint()..color = AppColors.primary;
    canvas.drawRect(rect, fill);

    final stroke = Paint()
      ..color = _gold.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    var row = 0;
    for (var y = 0.0; y < size.height; y += _cell, row++) {
      final shift = row.isEven ? 0.0 : -_cell / 2;
      for (var x = shift; x < size.width; x += _cell) {
        final path = Path()
          ..moveTo(x, y + _cell)
          ..lineTo(x + _cell / 2, y)
          ..lineTo(x + _cell, y + _cell)
          ..close();
        canvas.drawPath(path, stroke);
      }
    }

    // Inner gold rim.
    final rim = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(6), const Radius.circular(AppRadii.md8)),
      rim,
    );
  }

  @override
  bool shouldRepaint(covariant _CardBackPainter oldDelegate) => false;
}
