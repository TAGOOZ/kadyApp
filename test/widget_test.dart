import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots to Arabic welcome screen in RTL',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: KadyApp()));
    await tester.pump();

    expect(find.text('كافيه القاضي'), findsOneWidget);

    final titleContext = tester.element(find.text('كافيه القاضي'));
    expect(Directionality.of(titleContext), TextDirection.rtl);
  });

  testWidgets('Guest skip lands on the customer shell with 4 tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: KadyApp()));
    await tester.pump();

    await tester.tap(find.text('تخطي الآن'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('الرئيسية'), findsWidgets);
    expect(find.text('القائمة'), findsOneWidget);
    expect(find.text('الألعاب'), findsOneWidget);
    expect(find.text('حسابي'), findsOneWidget);
  });
}
