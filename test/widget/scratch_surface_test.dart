import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/games_prizes.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
import 'package:kady_app/ui/games/match/match_screen.dart';
import 'package:kady_app/ui/games/scratch/scratch_screen.dart';
import 'package:kady_app/ui/games/scratch/widgets/scratch_surface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loyalty state seeded with game tokens — supabase is NOT initialized in
/// widget tests; LoyaltyController degrades to local-only persistence (all
/// network paths are caught), which is exactly the scenario under test.
class SeededLoyalty extends LoyaltyController {
  @override
  LoyaltyState build() =>
      const LoyaltyState(matchTokens: 1, scratchTokens: 1);
}

Future<void> _pump(WidgetTester tester, Widget child,
    {bool seeded = false}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides:
          seeded ? [loyaltyProvider.overrideWith(SeededLoyalty.new)] : [],
      child: MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ScratchSurface coating', () {
    testWidgets('wide serpentine drag reveals the card and fires the callback',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var revealed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 200,
                child: ScratchSurface(
                  key: const Key('surface'),
                  onReveal: () => revealed = true,
                  child:
                      const Center(child: Text('١٠ نقاط هدية ⭐')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(revealed, isFalse);
      final origin = tester.getTopLeft(find.byKey(const Key('surface')));

      // Serpentine strokes across the full coating.
      const rows = [20.0, 55.0, 90.0, 125.0, 165.0];
      for (var i = 0; i < rows.length; i++) {
        final y = rows[i];
        final leftToRight = i.isEven;
        await tester.dragFrom(
          origin + Offset(leftToRight ? 10 : 290, y),
          Offset(leftToRight ? 280 : -280, 0),
        );
        await tester.pump();
      }

      await tester.pumpAndSettle();
      expect(revealed, isTrue,
          reason: '≥55% erased must auto-complete the reveal');
      // Prize layer text now fully visible.
      expect(find.text('١٠ نقاط هدية ⭐'), findsOneWidget);
    });

    testWidgets('short scratch does not auto-reveal', (tester) async {
      var revealed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 200,
                child: ScratchSurface(
                  onReveal: () => revealed = true,
                  child: const ColoredBox(color: Colors.amber),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(find.byType(ScratchSurface), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(revealed, isFalse);
    });
  });

  group('token gates', () {
    testWidgets('match screen shows locked panel with zero tokens',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester, const MatchScreen());

      expect(find.byKey(const Key('match-locked-panel')), findsOneWidget);
      expect(find.text('توكنات: 0'), findsOneWidget);
    });

    testWidgets('scratch screen shows locked panel with zero tokens',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester, const ScratchScreen());

      expect(find.byKey(const Key('scratch-locked-panel')), findsOneWidget);
      expect(find.text('توكنات: 0'), findsOneWidget);
    });
  });

  group('playable rounds', () {
    testWidgets('match round consumes token, reveals three cards and pops the result sheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Replicate the screen's exact rng consumption to know the outcome.
      final expectedOutcome = MatchRound.pick(Random(42));
      await _pump(tester, MatchScreen(rng: Random(42)), seeded: true);

      expect(find.byKey(const Key('match-locked-panel')), findsNothing);
      expect(find.byKey(const Key('match-attempts-chip')), findsNothing,
          reason: 'counter appears at round start');

      // First tap starts the round: token consumed, chip reads ٣.
      await tester.tap(find.byKey(const Key('match-card-0')));
      await tester.pump();
      expect(find.text('محاولات: ٣'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('محاولات: ٢'), findsOneWidget);

      await tester.tap(find.byKey(const Key('match-card-1')));
      await tester.pumpAndSettle();
      expect(find.text('محاولات: ١'), findsOneWidget);

      await tester.tap(find.byKey(const Key('match-card-2')));
      await tester.pumpAndSettle();

      // Advance past the post-flip delay before the sheet appears.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      if (expectedOutcome == MatchOutcome.none) {
        expect(find.text('حظ أوفر'), findsOneWidget);
      } else {
        expect(find.text('مبروك 🎉'), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('game-claim')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('game-claim')));
      await tester.pumpAndSettle();

      // Sheet closed → fresh face-down session; token was consumed at start.
      expect(find.byKey(const Key('match-attempts-chip')), findsNothing);
      expect(find.byKey(const Key('match-token-chip')), findsOneWidget);
    });

    testWidgets('scratch round consumes token on first stroke and enables استلم المكافأة after reveal',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final seed = 42;
      final expectedPrize = roll(Random(seed));
      await _pump(tester, ScratchScreen(rng: Random(seed)), seeded: true);

      final claimButton = find.byKey(const Key('scratch-claim-button'));
      expect(tester.widget<FilledButton>(claimButton).onPressed, isNull,
          reason: 'claim disabled until revealed');

      // Serpentine strokes covering the whole coating (row spacing < 2 ×
      // brush radius ⇒ every grid cell gets erased).
      final origin = tester.getTopLeft(find.byType(ScratchSurface));
      final size = tester.getSize(find.byType(ScratchSurface));
      final rowCount = (size.height / 40).ceil();
      for (var i = 0; i < rowCount; i++) {
        final leftToRight = i.isEven;
        final y = size.height * ((i + 0.5) / rowCount);
        await tester.dragFrom(
          origin + Offset(leftToRight ? 8 : size.width - 8, y),
          Offset(leftToRight ? size.width - 16 : -(size.width - 16), 0),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(claimButton).onPressed, isNotNull,
          reason: 'reveal must enable claim');
      expect(
        find.text(expectedPrize.labelAr),
        findsOneWidget,
        reason: 'prize layer shows the pre-picked weighted prize',
      );

      await tester.tap(claimButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('game-claim')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('game-claim')));
      await tester.pumpAndSettle();

      // Token burned at round start → back to locked panel afterwards.
      expect(find.byKey(const Key('scratch-locked-panel')), findsOneWidget);
    });
  });
}
