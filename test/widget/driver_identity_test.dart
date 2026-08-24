// RED test for driver identity (#019): real Supabase profile vs stub.
// Verifies AppBar shows profiles.display_name where user_id==auth.uid()
// and role==driver, with fallback to strings.driverNameStub.
// This test MUST fail before GREEN (DriverHomeScreen still shows stub).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kady_app/core/riverpod_retry.dart';
import 'package:kady_app/data/repos/driver_orders_repository.dart';
import 'package:kady_app/ui/driver/driver_home_screen.dart';

/// Fake repo that can script display_name and optionally delay/error.
class FakeDriverIdentityRepo implements DriverOrdersRepo {
  FakeDriverIdentityRepo({
    this.displayName,
    this.displayNameFuture,
    this.shouldThrow = false,
  });

  String? displayName;
  Future<String?>? displayNameFuture;
  bool shouldThrow;

  final controller = StreamController<List<DriverOrder>>.broadcast();
  Object? accessError;

  @override
  Future<String?> fetchDriverDisplayName() async {
    if (shouldThrow) throw Exception('profile fetch failed');
    if (displayNameFuture != null) return displayNameFuture;
    return displayName;
  }

  @override
  Stream<List<DriverOrder>> streamAssigned() => controller.stream;

  @override
  Future<void> accept(String orderId) async {}

  @override
  Future<void> markPickedUp(String orderId) async {}

  @override
  Future<void> markDelivered(String orderId) async {}

  @override
  Future<List<DriverOrder>> fetchHistory() async => const [];

  @override
  Future<String?> fetchAddressText(String addressId) async => null;

  @override
  Future<List<String>> fetchEventStatuses(String orderId) async => const [];

  @override
  Future<Map<String, String>> fetchCustomerNames() async => const {};

  @override
  Future<void> ensureDriverAccess() async {
    final error = accessError;
    if (error != null) throw error;
  }
}

Future<void> _pumpDriverHome(
  WidgetTester tester,
  FakeDriverIdentityRepo repo,
) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutoRetry,
      overrides: [driverOrdersRepoProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: DriverHomeScreen(),
        ),
      ),
    ),
  );
  await tester.pump(); // access probe + profile future first frame
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('shows real driver name when profile available', (tester) async {
    final repo = FakeDriverIdentityRepo(displayName: 'أحمد س.');
    await _pumpDriverHome(tester, repo);

    // AppBar should show real name, not stub.
    expect(find.text('أحمد س.'), findsOneWidget);
    expect(find.text('كريم م.'), findsNothing);
    // CircleAvatar stays.
    expect(find.byType(CircleAvatar), findsOneWidget);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('falls back to stub when display_name is null', (tester) async {
    final repo = FakeDriverIdentityRepo(displayName: null);
    await _pumpDriverHome(tester, repo);

    expect(find.text('كريم م.'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsOneWidget);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('falls back to stub when display_name is empty', (tester) async {
    final repo = FakeDriverIdentityRepo(displayName: '   ');
    await _pumpDriverHome(tester, repo);

    expect(find.text('كريم م.'), findsOneWidget);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('falls back to stub on profile fetch error', (tester) async {
    final repo = FakeDriverIdentityRepo(shouldThrow: true);
    await _pumpDriverHome(tester, repo);

    expect(find.text('كريم م.'), findsOneWidget);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('loading shows stub until profile resolves', (tester) async {
    final completer = Completer<String?>();
    final repo = FakeDriverIdentityRepo(
      displayNameFuture: completer.future,
    );
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        retry: noAutoRetry,
        overrides: [
          driverOrdersRepoProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: DriverHomeScreen(),
          ),
        ),
      ),
    );
    await tester.pump(); // first frame, profile still loading
    expect(find.text('كريم م.'), findsOneWidget);
    expect(find.text('أحمد س.'), findsNothing);

    completer.complete('أحمد س.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('أحمد س.'), findsOneWidget);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  });
}
