import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
import 'package:kady_app/ui/games/spinner/spinner_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SeededSpinnerLoyalty extends LoyaltyController {
  _SeededSpinnerLoyalty(this.tokens);
  final int tokens;
  @override
  LoyaltyState build() => LoyaltyState(spinnerTokens: tokens);
}

class FixedRandom implements Random {
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  int seededSpinner = 0,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [loyaltyProvider.overrideWith(() => _SeededSpinnerLoyalty(seededSpinner))],
      child: MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('locked panel when no tokens', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, const SpinnerScreen());
    expect(find.byKey(const Key('spinner-locked-panel')), findsOneWidget);
    expect(find.byKey(const Key('spinner-spin-button')), findsNothing);
    expect(find.byKey(const Key('spinner-token-chip')), findsOneWidget);
  });

  testWidgets('token chip shows seeded count', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, const SpinnerScreen(), seededSpinner: 2);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.byKey(const Key('spinner-locked-panel')), findsNothing);
    expect(find.byKey(const Key('spinner-spin-button')), findsOneWidget);
  });

  testWidgets('legend lists all prizes', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, const SpinnerScreen(), seededSpinner: 1);
    expect(find.byKey(const Key('spinner-legend')), findsOneWidget);
    expect(find.byKey(ValueKey('spinner-legend-pts5')), findsOneWidget);
    expect(find.byKey(ValueKey('spinner-legend-toppingVoucher')), findsOneWidget);
    expect(find.byKey(ValueKey('spinner-legend-nothing')), findsOneWidget);
  });

  testWidgets('spin consumes token, animates wheel, result sheet claims prize', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, SpinnerScreen(rng: FixedRandom()), seededSpinner: 1);

    expect(find.byKey(const Key('spinner-spin-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('spinner-spin-button')));
    await tester.pumpAndSettle();

    // token consumed
    expect(find.textContaining('0'), findsWidgets);
    // result sheet appears (FixedRandom nextDouble=0 → roll pts5)
    expect(find.byKey(const ValueKey('game-claim')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('game-claim')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(SpinnerScreen)));
    expect(container.read(loyaltyProvider).points, 5);
    expect(container.read(loyaltyProvider).spinnerTokens, 0);
    // back to locked after round
    expect(find.byKey(const Key('spinner-locked-panel')), findsOneWidget);
  });
}
