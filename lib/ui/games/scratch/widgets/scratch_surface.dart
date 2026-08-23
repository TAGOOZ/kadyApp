// ScratchSurface (#009): prize layer beneath a silver-gray coating painted by
// CustomPainter. Pointer strokes punch through the coating with
// BlendMode.clear; progress is tracked on an virtual grid and at ≥55% erased
// the card auto-completes (full reveal + sparkle Icon burst).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Auto-complete once this fraction of the estimated area is scratched away.
const double kScratchAutoRevealRatio = 0.55;

class ScratchSurface extends StatefulWidget {
  const ScratchSurface({
    super.key,
    required this.child,
    required this.onReveal,
    this.onScratchStart,
    this.autoRevealAt = kScratchAutoRevealRatio,
    this.brushRadius = 24,
    this.enabled = true,
  });

  /// Prize layer shown beneath the coating.
  final Widget child;

  /// Fires once when the erased ratio reaches [autoRevealAt].
  final VoidCallback onReveal;

  /// Fires once on the very first scratch stroke — the screen uses it to
  /// consume the round's scratchToken at round start.
  final VoidCallback? onScratchStart;

  final double autoRevealAt;
  final double brushRadius;
  final bool enabled;

  @override
  State<ScratchSurface> createState() => _ScratchSurfaceState();
}

class _ScratchSurfaceState extends State<ScratchSurface> {
  final List<Offset> _erasedPoints = <Offset>[];
  final Set<int> _erasedCells = <int>{};
  bool _revealed = false;
  bool _startSent = false;

  static const int _gridCellPx = 18;

  void _onPointerDown(PointerEvent event) =>
      _scratch(event.localPosition);

  void _onPointerMove(PointerEvent event) {
    if (_erasedPoints.isEmpty) {
      _scratch(event.localPosition);
      return;
    }
    // Sample along the stroke so fast swipes leave no gaps.
    final last = _erasedPoints.last;
    final delta = event.localPosition - last;
    final distance = delta.distance;
    final steps = math.max(1, distance ~/ (widget.brushRadius / 3));
    for (var i = 1; i <= steps; i++) {
      _scratch(last + delta * (i / steps));
    }
  }

  void _scratch(Offset point) {
    if (_revealed || !widget.enabled) return;
    if (!_startSent) {
      _startSent = true;
      widget.onScratchStart?.call();
    }
    setState(() {
      _erasedPoints.add(point);
      _markCells(point);
    });
    _checkReveal();
  }

  void _markCells(Offset p) {
    final size = _surfaceSize;
    if (size == null || size.isEmpty) return;
    final cols = math.max(1, size.width ~/ _gridCellPx);
    final rows = math.max(1, size.height ~/ _gridCellPx);
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    final r = widget.brushRadius;
    final c0 = ((p.dx - r) / cellW).floor().clamp(0, cols - 1);
    final c1 = ((p.dx + r) / cellW).floor().clamp(0, cols - 1);
    final rw0 = ((p.dy - r) / cellH).floor().clamp(0, rows - 1);
    final rw1 = ((p.dy + r) / cellH).floor().clamp(0, rows - 1);
    for (var c = c0; c <= c1; c++) {
      for (var rw = rw0; rw <= rw1; rw++) {
        _erasedCells.add(rw * cols + c);
      }
    }
  }

  Size? get _surfaceSize {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size : null;
  }

  double get erasedRatio {
    final size = _surfaceSize;
    if (size == null || size.isEmpty) return 0;
    final total =
        math.max(1, size.width ~/ _gridCellPx) *
            math.max(1, size.height ~/ _gridCellPx);
    return _erasedCells.length / total;
  }

  void _checkReveal() {
    if (_revealed || erasedRatio < widget.autoRevealAt) return;
    setState(() => _revealed = true);
    widget.onReveal();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Prize layer beneath the coating.
        widget.child,
        // Coating (fades out fully once revealed).
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _revealed,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _revealed ? 0 : 1,
              child: RepaintBoundary(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: widget.enabled ? _onPointerDown : null,
                  onPointerMove: widget.enabled ? _onPointerMove : null,
                  child: CustomPaint(
                    key: const Key('scratch-coating'),
                    size: Size.infinite,
                    painter: _CoatingPainter(
                      points: List.unmodifiable(_erasedPoints),
                      brushRadius: widget.brushRadius,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Sparkle Icon burst on auto-complete.
        if (_revealed)
          const Positioned.fill(
            child: IgnorePointer(
              child: AnimatedScale(
                scale: 1,
                duration: Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFFE7C77B), size: 30),
                      SizedBox(width: AppSpacing.xs8),
                      Icon(Icons.auto_awesome,
                          color: AppColors.secondary, size: 44),
                      SizedBox(width: AppSpacing.xs8),
                      Icon(Icons.auto_awesome, color: Color(0xFFE7C77B), size: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Silver-gray coating; [points] are punched out via BlendMode.clear inside a
/// saveLayer so the prize layer shows through the stroked path only.
class _CoatingPainter extends CustomPainter {
  const _CoatingPainter({required this.points, required this.brushRadius});

  final List<Offset> points;
  final double brushRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());

    const silverLight = Color(0xFFE7EBE7);
    const silverDark = Color(0xFFD6DBD6); // #E0E3E0-ish family
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [silverLight, silverDark, silverLight],
        ).createShader(bounds),
    );

    // Faint diagonal sheen streaks.
    final sheen = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    for (final t in const [0.25, 0.5, 0.75]) {
      canvas.drawLine(
        Offset(size.width * t - 30, size.height * 0.15),
        Offset(size.width * t + 30, size.height * 0.85),
        sheen,
      );
    }

    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = brushRadius * 2;
    final dot = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;

    if (points.length == 1) {
      canvas.drawCircle(points.first, brushRadius, dot);
    }
    for (var i = 1; i < points.length; i++) {
      canvas.drawLine(points[i - 1], points[i], clear);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CoatingPainter oldDelegate) =>
      oldDelegate.points.length != points.length ||
      oldDelegate.brushRadius != brushRadius;
}
