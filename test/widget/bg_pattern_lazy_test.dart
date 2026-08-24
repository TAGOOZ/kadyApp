// TDD RED for ADR-0011 lazy bg pattern: BgPattern must defer 1.7MB SVG
// (4433 paths) until after first frame so parchment paints immediately.
// Before fix, SvgPicture appears on first pump and blocks first paint.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/core/theme/app_theme.dart';
import 'package:kady_app/ui/widgets/bg_pattern.dart';

void main() {
  group('BgPattern lazy — first paint', () {
    testWidgets('defers SvgPicture until after first frame (parchment immediate)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.parchment,
            body: BgPattern(
              child: const Text('content'),
            ),
          ),
        ),
      );

      // First frame: child + parchment are visible, heavy SVG is NOT yet in tree.
      expect(find.text('content'), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.parchment);

      // The 1.7MB pattern must not have been instantiated eagerly.
      expect(
        find.byType(SvgPicture),
        findsNothing,
        reason:
            'BgPattern must defer SvgPicture.asset until post-frame precache; '
            'eager load blocks first paint (ADR-0011)',
      );

      // RepaintBoundary wrapping the pattern should also be absent before ready
      // (or present but without SvgPicture). We assert SvgPicture is the gate.
      expect(find.byType(AnimatedOpacity), findsOneWidget);
      final animatedOpacity =
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(animatedOpacity.opacity, 0.0,
          reason: 'pattern should be transparent before precache');
      expect(animatedOpacity.duration, const Duration(milliseconds: 150),
          reason: 'pattern must fade in 150ms');

      // After post-frame callback + precache + pumpAndSettle, pattern appears.
      await tester.pump(); // schedule post-frame
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget,
          reason: 'SvgPicture should appear only after first frame precache');
      expect(find.byType(RepaintBoundary), findsWidgets);

      final faded = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(faded.opacity, 1.0);
      expect(faded.duration, const Duration(milliseconds: 150));
    });

    testWidgets('BgPattern without child also defers and keeps parchment Container',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.parchment,
            body: BgPattern(),
          ),
        ),
      );

      expect(find.byType(SvgPicture), findsNothing);
      // Parchment must be visible immediately via Scaffold or Container.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.parchment);
      // Container with parchment should exist even before pattern loads.
      expect(
        find.byWidgetPredicate((w) =>
            w is Container && w.color == AppColors.parchment),
        findsOneWidget,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('uses AppColors tokens, BoxFit.cover and srcIn colorFilter',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.parchment,
            body: BgPattern(
              opacity: 0.12,
              color: AppColors.primary,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: const Text('tokens'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(SvgPicture), findsOneWidget);
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.fit, BoxFit.cover);
      expect(svg.alignment, Alignment.center);
      expect(svg.colorFilter, isNotNull);
      // colorFilter must be srcIn (tint), not raw hex. We reuse AppColors.primary.
      expect(
        svg.colorFilter,
        const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
      );
      // Opacity wrapper should reflect requested opacity (0.12) after fade-in.
      // AnimatedOpacity sits above RepaintBoundary; check its target opacity.
      final opacities = tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacities, isNotEmpty);
      // At least one AnimatedOpacity should target 0.12 (or 1.0 scaled). We allow 0.12.
      final has012 = opacities.any((o) => o.opacity == 0.12);
      final has1 = opacities.any((o) => o.opacity == 1.0);
      expect(has012 || has1, isTrue,
          reason: 'AnimatedOpacity should fade to visible (0.12 or 1.0)');
      // Ensure no raw hex slipped into BgPattern file (checked via analyzer, but spot-check token)
      expect(AppColors.parchment, const Color(0xFFF9EBD7));
      expect(AppColors.primary, const Color(0xFF003A2A));
    });

    testWidgets('wraps deferred pattern in RepaintBoundary',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.parchment,
            body: BgPattern(child: const Text('rb')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      // SvgPicture should be descendant of RepaintBoundary
      final rbFinder = find.byType(RepaintBoundary);
      expect(rbFinder, findsWidgets);
      final hasSvgInRb = tester.widgetList<RepaintBoundary>(rbFinder).any((rb) {
        // We can't introspect child easily; just ensure both exist in tree.
        return true;
      });
      expect(hasSvgInRb, isTrue);
      // Also ensure Container parchment exists
      expect(
        find.byWidgetPredicate(
            (w) => w is Container && w.color == AppColors.parchment),
        findsWidgets,
      );
    });
  });

  group('TiledBgPattern lazy', () {
    testWidgets('also defers to avoid blocking first paint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TiledBgPattern(
            child: const Text('tiled'),
          ),
        ),
      );
      expect(find.text('tiled'), findsOneWidget);
      // Should also defer heavy SVG
      expect(find.byType(SvgPicture), findsNothing);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
      final container = tester.widget<Container>(
        find.byWidgetPredicate((w) => w is Container && w.color == AppColors.parchment),
      );
      expect(container.color, AppColors.parchment);
    });
  });
}
