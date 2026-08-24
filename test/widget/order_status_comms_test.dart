// TDD RED → GREEN for order/driver comms (feat/018): OrderStatus
// previously only snack-barred 'الاتصال قريبًا' / 'الاتجاهات المباشرة قريبًا'.
// Now it tries tel:+20 and Google Maps via url_launcher (canLaunchUrl +
// launchUrl externalApplication) and only falls back to Clipboard + SnackBar
// when launching is unavailable. These tests mock the launcher via a fake
// AppLauncher provider override and assert the launch URIs, failing before
// the impl existed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/core/launcher/app_launcher.dart';
import 'package:kady_app/core/riverpod_retry.dart';
import 'package:kady_app/data/repos/order_status_repository.dart';
import 'package:kady_app/domain/order_status_flow.dart';
import 'package:kady_app/ui/orders/order_status_screen.dart';
import 'package:kady_app/ui/orders/widgets/driver_card.dart';

class _FakeLauncher implements AppLauncher {
  final List<Uri> canLaunchCalls = [];
  final List<Uri> launchCalls = [];
  final List<String> copies = [];
  bool canLaunchResult = true;
  bool launchResult = true;

  @override
  Future<bool> canLaunchUrl(Uri uri) async {
    canLaunchCalls.add(uri);
    return canLaunchResult;
  }

  @override
  Future<bool> launchUrl(Uri uri, {LaunchMode mode = LaunchMode.externalApplication}) async {
    launchCalls.add(uri);
    return launchResult;
  }

  @override
  Future<void> copy(String text) async {
    copies.add(text);
  }
}

CustomerOrder _order({
  required String modeWire,
  required OrderWireStatus status,
  bool hasDriver = false,
}) {
  return CustomerOrder(
    id: 'o1',
    displayNumber: 1023,
    modeWire: modeWire,
    status: status,
    createdAtUtc: DateTime.utc(2026, 8, 22, 9),
    hasDriver: hasDriver,
  );
}

class _FakeOrderStatusRepo implements OrderStatusRepo {
  final _orderController = StreamController<CustomerOrder?>.broadcast();
  void emit(CustomerOrder order) => _orderController.add(order);
  @override
  Stream<CustomerOrder?> watchOrder(String orderId) => _orderController.stream;
  @override
  Stream<List<CustomerOrder>> watchOwnOrders(String googleUserId) => const Stream.empty();
  @override
  Future<List<CustomerOrder>> fetchOwnOrders(String googleUserId) async => const [];
  @override
  Future<List<OrderEventRow>> fetchEvents(String orderId) async => const [];
}

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this._lang);
  final AppLang _lang;
  @override
  AppLang build() => _lang;
}

Future<({ _FakeOrderStatusRepo repo, _FakeLauncher launcher })> _pump(
  WidgetTester tester, {
  AppLang lang = AppLang.ar,
  _FakeLauncher? launcher,
}) async {
  final repo = _FakeOrderStatusRepo();
  final fakeLauncher = launcher ?? _FakeLauncher();
  await tester.pumpWidget(
    ProviderScope(
      retry: noAutoRetry,
      overrides: [
        orderStatusRepoProvider.overrideWithValue(repo),
        localeNotifierProvider.overrideWith(() => _FixedLocale(lang)),
        appLauncherProvider.overrideWithValue(fakeLauncher),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: OrderStatusScreen(orderId: 'o1'),
        ),
      ),
    ),
  );
  await tester.pump();
  return (repo: repo, launcher: fakeLauncher);
}

void main() {
  group('OrderStatus comms — tel & maps via url_launcher', () {
    testWidgets('driver call launches tel:+20 via canLaunchUrl + launchUrl', (tester) async {
      final fake = _FakeLauncher();
      final (:repo, :launcher) = await _pump(tester, launcher: fake);
      final captured = launcher;
      expect(captured.launchCalls, isEmpty);

      repo.emit(_order(
        modeWire: 'delivery',
        status: OrderWireStatus.outForDelivery,
        hasDriver: true,
      ));
      await tester.pump();

      expect(find.byType(DriverCard), findsOneWidget);
      await tester.tap(find.byIcon(Icons.phone_outlined));
      await tester.pump();
      // allow async launcher calls to settle
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured.canLaunchCalls, isNotEmpty);
      expect(captured.launchCalls, isNotEmpty);
      final telUri = captured.launchCalls.first;
      expect(telUri.scheme, 'tel');
      expect(telUri.path, contains('+20'));
    });

    testWidgets('directions launches Google Maps search URL', (tester) async {
      final fake = _FakeLauncher();
      final (:repo, :launcher) = await _pump(tester, launcher: fake);
      final captured = launcher;

      repo.emit(_order(
        modeWire: 'delivery',
        status: OrderWireStatus.outForDelivery,
        hasDriver: true,
      ));
      await tester.pump();

      await tester.ensureVisible(find.text('فتح الاتجاهات'));
      await tester.pump();
      await tester.tap(find.text('فتح الاتجاهات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(captured.canLaunchCalls, isNotEmpty);
      expect(captured.launchCalls, isNotEmpty);
      final mapsUri = captured.launchCalls.firstWhere(
        (u) => u.toString().contains('google.com/maps/search'),
        orElse: () => captured.launchCalls.first,
      );
      expect(
        mapsUri.toString(),
        startsWith('https://www.google.com/maps/search/?api=1&query='),
      );
      expect(mapsUri.toString(), isNot(contains(' ')));
    });

    testWidgets('when canLaunch is false fallback copies and snacks', (tester) async {
      final fake = _FakeLauncher()..canLaunchResult = false;
      final (:repo, :launcher) = await _pump(tester, launcher: fake);

      repo.emit(_order(
        modeWire: 'delivery',
        status: OrderWireStatus.outForDelivery,
        hasDriver: true,
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.phone_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(launcher.launchCalls, isEmpty);
      expect(launcher.copies, isNotEmpty);
      expect(launcher.copies.first, contains('+20'));
      expect(find.text('الاتصال قريبًا'), findsOneWidget);
    });

    testWidgets('fallback for maps copies url and snacks', (tester) async {
      final fake = _FakeLauncher()..canLaunchResult = false;
      final (:repo, :launcher) = await _pump(tester, launcher: fake);

      repo.emit(_order(
        modeWire: 'delivery',
        status: OrderWireStatus.outForDelivery,
        hasDriver: true,
      ));
      await tester.pump();

      await tester.ensureVisible(find.text('فتح الاتجاهات'));
      await tester.pump();
      await tester.tap(find.text('فتح الاتجاهات'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(launcher.launchCalls, isEmpty);
      expect(launcher.copies, isNotEmpty);
      expect(
        launcher.copies.first,
        startsWith('https://www.google.com/maps/search/?api=1&query='),
      );
      expect(find.text('الاتجاهات المباشرة قريبًا'), findsOneWidget);
    });
  });
}
