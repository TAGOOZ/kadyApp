import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kady_app/data/repos/customers_repository.dart';
import 'package:kady_app/domain/auth_controller.dart';
import 'package:kady_app/ui/auth/phone_collection_screen.dart';

class _StubGateway implements AuthGateway {
  final _events = StreamController<GoogleProfile?>.broadcast();

  @override
  Future<GoogleProfile?> restoreSession() async => null;

  @override
  Stream<GoogleProfile?> get authStateChanges => _events.stream;

  @override
  Future<bool> signInWithGoogle(String redirectTo) async => true;

  @override
  Future<void> signOut() async {}

  Future<void> dispose() => _events.close();
}

class _StubRepo implements CustomersRepo {
  int upsertCalls = 0;

  @override
  Future<CustomerRecord?> findByGoogleUserId(String googleUserId) async =>
      null;

  @override
  Future<CustomerRecord> upsert(CustomerUpsert customer) async {
    upsertCalls++;
    return CustomerRecord(phone: customer.phone, name: customer.name);
  }
}

Future<ProviderContainer> _pump(WidgetTester tester, _StubGateway gateway) async {
  final container = ProviderContainer(
    overrides: [
      authGatewayProvider.overrideWithValue(gateway),
      customersRepoProvider.overrideWithValue(const _NeverRepo()),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: MaterialApp(home: const PhoneCollectionScreen()),
      ),
    ),
  );
  return container;
}

class _NeverRepo implements CustomersRepo {
  const _NeverRepo();

  @override
  Future<CustomerRecord?> findByGoogleUserId(String googleUserId) async =>
      null;

  @override
  Future<CustomerRecord> upsert(CustomerUpsert customer) async {
    throw StateError('repo should not be hit before validation passes');
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('bad phone input shows the inline Arabic validation error',
      (tester) async {
    final gateway = _StubGateway();
    addTearDown(gateway.dispose);
    final container = await _pump(tester, gateway);
    addTearDown(container.dispose);
    await tester.pump();

    await tester.enterText(find.byKey(const Key('auth_phone_field')), '12345');
    await tester.tap(find.byKey(const Key('auth_save_button')));
    await tester.pump();

    expect(
      find.text('أدخل رقمًا صحيحًا مثل +201001234567'),
      findsOneWidget,
    );
  });

  testWidgets('valid phone passes validation and submits once',
      (tester) async {
    final gateway = _StubGateway();
    addTearDown(gateway.dispose);

    final repo = _StubRepo();
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        customersRepoProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(home: const PhoneCollectionScreen()),
        ),
      ),
    );
    await tester.pump();

    // Name is required by the form; fill it alongside a valid number.
    await tester.enterText(find.byType(TextFormField).at(1), 'أحمد');
    await tester.enterText(find.byKey(const Key('auth_phone_field')),
        '01001234567');
    await tester.tap(find.byKey(const Key('auth_save_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('أدخل رقمًا صحيحًا مثل +201001234567'),
      findsNothing,
    );
    expect(repo.upsertCalls, 1);
  });
}
