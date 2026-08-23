import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/l10n/strings_spinner.dart';
import 'package:kady_app/domain/spinner_engine.dart';
import 'package:kady_app/ui/games/spinner/spinner_screen.dart';
import 'package:kady_app/ui/games/spinner/widgets/result_modal.dart';
import 'package:kady_app/ui/games/spinner/widgets/spinner_wheel.dart';

void main() {
  // Supabase is NOT initialized in widget tests; LoyaltyController degrades to
  // a local zero state (all network paths are caught), which is exactly the
  // locked scenario under test.

  testWidgets('locked state: panel shown, spin hub disabled',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SpinnerScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spinner-locked-panel')), findsOneWidget);
    expect(find.text('توكنات: 0'), findsOneWidget);

    final hub = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(SpinnerWheel),
        matching: find.byType(FilledButton),
      ),
    );
    expect(hub.onPressed, isNull, reason: 'no tokens → spin disabled');
  });

  testWidgets('wheel renders six slices with hub button when tokens exist is irrelevant here — smoke', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SpinnerScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SpinnerWheel), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  group('ResultModal mapping (pure UI over prize)', () {
    for (final prize in SpinPrize.values) {
      testWidgets('${prize.name} renders correct title/icon color',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ResultModal(prize: prize, strings: SpinnerStrings.of(AppLang.ar)),
            ),
          ),
        );
        expect(find.byIcon(prize.icon), findsOneWidget);
        if (prize == SpinPrize.nothing) {
          expect(find.text('حظ أوفر المرة الجاية 😅'), findsOneWidget);
        } else {
          expect(find.text('مبروك! 🎉'), findsOneWidget);
          expect(find.text(prize.labelAr), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('spinner-claim')), findsOneWidget);
      });
    }
  });
}
