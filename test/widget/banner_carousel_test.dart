// Widget tests for the banner carousel reduce-motion regression: auto-
// advance must never start — nor be resurrected by a pointer interaction —
// under MediaQuery.disableAnimations, while normal motion still advances
// on cadence (audit finding #3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/l10n/strings_home.dart';
import 'package:kady_app/ui/home/widgets/banner_carousel.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool disableAnimations,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          // Overrides MaterialApp's default so the carousel sees the
          // reduce-motion preference.
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: BannerCarousel(
            strings: HomeStringsCatalog.of(AppLang.ar),
            onTapBanner: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

int _activeIndex(WidgetTester tester) => tester
    .widget<HomeDotsIndicator>(find.byType(HomeDotsIndicator))
    .activeIndex;

void main() {
  testWidgets('reduce-motion: no auto-advance even without interaction',
      (tester) async {
    await _pump(tester, disableAnimations: true);

    expect(_activeIndex(tester), 0);
    await tester.pump(const Duration(seconds: 12));
    expect(_activeIndex(tester), 0);
  });

  testWidgets('reduce-motion: drag does not resurrect the auto-advance timer',
      (tester) async {
    await _pump(tester, disableAnimations: true);

    // Manual swipe still works; only the timer must stay dead.
    await tester.drag(find.byType(PageView), const Offset(-480, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_activeIndex(tester), 1);

    // Pointer-up restart path is guarded → past two cadence windows the
    // page has not moved.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_activeIndex(tester), 1);
  });

  testWidgets('normal motion: timer restarts after a drag and advances',
      (tester) async {
    await _pump(tester, disableAnimations: false);

    await tester.drag(find.byType(PageView), const Offset(-480, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(_activeIndex(tester), 1);

    // Auto-advance tick on the restarted 5s cadence.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_activeIndex(tester), 2);
  });
}
