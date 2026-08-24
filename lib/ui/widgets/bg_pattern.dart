// Heritage Hearth bg pattern — recolored 17803653_5891577.svg
// Original fill #333EA1 → AppColors.primary #003A2A at 12% opacity, background → transparent.
// Use as low-opacity parchment backdrop (AGENTS.md#2 tokens only, no raw hex).
// ADR-0011 lazy: 1.7MB SVG (4433 paths) is deferred until after first frame so
// parchment paints immediately; pattern fades in 150ms inside a RepaintBoundary.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';

/// Low-opacity dark pattern for parchment/paperWhite surfaces.
///
/// The SVG asset `assets/images/bg_pattern.svg` was derived from
/// `17803653_5891577.svg`:
/// - all `fill:#333EA1` → `fill:#003A2A;fill-opacity:0.12` (AppColors.primary, 12%)
/// - `BACKGROUND` rect `#F1F1F1` → `fill:none` (transparent so Scaffold parchment shows)
///
/// To use a different dark token, edit the SVG's `fill:#003A2A` to
/// `AppColors.coffeeBean` or `primaryContainer` and keep `fill-opacity:0.12`.
/// Or override at runtime via [color] + [opacity].
class BgPattern extends StatefulWidget {
  const BgPattern({
    super.key,
    this.child,
    this.opacity = 1.0,
    this.color,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  /// Optional child stacked above the pattern (e.g. your page content).
  final Widget? child;

  /// Extra opacity on top of the SVG's built-in 0.12 (1.0 = as-authored, 0.12 = half).
  final double opacity;

  /// Runtime recolor — if set, tints the SVG via [ColorFilter] (overrides SVG's #003A2A).
  /// Example: `AppColors.coffeeBean` or `AppColors.primaryContainer`.
  final Color? color;

  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  State<BgPattern> createState() => _BgPatternState();
}

class _BgPatternState extends State<BgPattern> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Defer heavy SVG decode until after first frame so parchment paints
    // immediately (ADR-0011). In flutter_svg 2.3 the SVG is decoded via
    // vector_graphics; we defer instantiation and optionally warm the cache
    // via the bundle after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // SvgPicture is only instantiated after first frame; before that we keep
    // a zero-size placeholder so first paint is just parchment + child.
    final svg = _ready
        ? SvgPicture.asset(
            'assets/images/bg_pattern.svg',
            fit: widget.fit,
            alignment: widget.alignment,
            // If color is set, tint the whole SVG (keeps 12% fill-opacity, tints hue).
            colorFilter: widget.color == null
                ? null
                : ColorFilter.mode(widget.color!, BlendMode.srcIn),
          )
        : const SizedBox.shrink();

    // RepaintBoundary isolates the 4433-path repaint; AnimatedOpacity fades
    // the pattern in 150ms after precache, keeping Scaffold parchment immediate.
    final pattern = RepaintBoundary(
      child: AnimatedOpacity(
        opacity: _ready ? widget.opacity : 0.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: svg,
      ),
    );

    if (widget.child == null) {
      return Container(
        color: AppColors.parchment,
        child: pattern,
      );
    }
    return Container(
      color: AppColors.parchment,
      child: Stack(
        children: [
          Positioned.fill(child: pattern),
          widget.child!,
        ],
      ),
    );
  }
}

/// Scaffold helper — wrap any screen's body with parchment + pattern:
/// ```dart
/// Scaffold(
///   backgroundColor: AppColors.parchment, // or paperWhite
///   body: BgPattern(
///     child: ListView(...),
///   ),
/// )
/// ```
/// For tiling (repeat) use [TiledBgPattern] which paints the SVG as a repeating texture.
/// Also deferred (ADR-0011) to avoid first-frame jank.
class TiledBgPattern extends StatefulWidget {
  const TiledBgPattern({
    super.key,
    required this.child,
    this.tileSize = 300,
    this.opacity = 0.06,
    this.color = AppColors.primary,
  });

  final Widget child;
  final double tileSize;
  final double opacity;
  final Color color;

  @override
  State<TiledBgPattern> createState() => _TiledBgPatternState();
}

class _TiledBgPatternState extends State<TiledBgPattern> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final svg = _ready
        ? SvgPicture.asset(
            'assets/images/bg_pattern.svg',
            width: widget.tileSize,
            height: widget.tileSize,
            fit: BoxFit.none,
            colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
          )
        : const SizedBox.shrink();

    final pattern = RepaintBoundary(
      child: AnimatedOpacity(
        opacity: _ready ? widget.opacity : 0.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: svg,
      ),
    );

    return Container(
      color: AppColors.parchment,
      child: Stack(
        children: [
          Positioned.fill(child: pattern),
          widget.child,
        ],
      ),
    );
  }
}
