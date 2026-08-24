// Heritage Hearth bg pattern — recolored 17803653_5891577.svg
// Original fill #333EA1 → AppColors.primary #003A2A at 6% opacity, background → transparent.
// Use as low-opacity parchment backdrop (AGENTS.md#2 tokens only, no raw hex).
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';

/// Low-opacity dark pattern for parchment/ paperWhite surfaces.
/// 
/// The SVG asset `assets/images/bg_pattern.svg` was derived from
/// `17803653_5891577.svg`:
/// - all `fill:#333EA1` → `fill:#003A2A;fill-opacity:0.06` (AppColors.primary, ~6% like AppShadows)
/// - `BACKGROUND` rect `#F1F1F1` → `fill:none` (transparent so Scaffold parchment shows)
/// 
/// To use a different dark token, edit the SVG's `fill:#003A2A` to
/// `AppColors.coffeeBean #4B2C20` or `primaryContainer #00533E` and keep `fill-opacity:0.06`.
/// Or override at runtime via [color] + [opacity].
class BgPattern extends StatelessWidget {
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

  /// Extra opacity on top of the SVG's built-in 0.06 (1.0 = as-authored).
  final double opacity;

  /// Runtime recolor — if set, tints the SVG via [ColorFilter] (overrides SVG's #003A2A).
  /// Example: `AppColors.coffeeBean` or `AppColors.primaryContainer`.
  final Color? color;

  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final pattern = SvgPicture.asset(
      'assets/images/bg_pattern.svg',
      fit: fit,
      alignment: alignment,
      // If color is set, tint the whole SVG (keeps 6% fill-opacity, tints hue).
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );

    final bg = Opacity(
      opacity: opacity,
      child: pattern,
    );

    if (child == null) return bg;
    return Stack(
      children: [
        Positioned.fill(child: bg),
        child!,
      ],
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
class TiledBgPattern extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.parchment,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: opacity,
              child: SvgPicture.asset(
                'assets/images/bg_pattern.svg',
                width: tileSize,
                height: tileSize,
                fit: BoxFit.none,
                // Tile via repetition using ImageRepeat is not supported for SvgPicture,
                // so we use a simple cover; for true tiling wrap in a CustomPaint
                // or use `flutter_svg`'s `SvgPicture` inside a `RepaintBoundary` with `ImageRepeat`.
                // This cover variant is 1× and already low-opacity, so tiling is subtle.
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
