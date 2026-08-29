import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
import 'package:kady_app/domain/loyalty_gateway.dart';
import 'package:kady_app/domain/loyalty_rules.dart';

class FakeLoyaltyGateway implements LoyaltyGateway {
  FakeLoyaltyGateway({
    this.currentUserId,
    Map<String, ({String phone, LoyaltyState state})>? byGoogleUserId,
    Map<String, dynamic>? config,
    this.throwOnFetchState = false,
    this.throwOnFetchConfig = false,
  })  : byGoogleUserId = byGoogleUserId ?? {},
        config = config ?? const {},
        stateByPhone = {
          for (final e in (byGoogleUserId ?? {}).values) e.phone: e.state,
        };

  @override
  String? currentUserId;
  final Map<String, ({String phone, LoyaltyState state})> byGoogleUserId;
  final Map<String, LoyaltyState> stateByPhone;
  Map<String, dynamic> config;
  bool throwOnFetchState;
  bool throwOnFetchConfig;

  @override
  Future<({String phone, LoyaltyState state})?> fetchState(String googleUserId) async {
    if (throwOnFetchState) throw Exception('fetchState fail');
    return byGoogleUserId[googleUserId];
  }

  @override
  Future<String?> fetchPhone(String googleUserId) async {
    if (throwOnFetchState) throw Exception('fetchPhone fail');
    return byGoogleUserId[googleUserId]?.phone;
  }

  @override
  Future<Map<String, dynamic>> fetchConfig() async {
    if (throwOnFetchConfig) throw Exception('config fail');
    return config;
  }

  @override
  Stream<LoyaltyState> watchState(String phone) {
    final s = stateByPhone[phone];
    return Stream.value(s ?? const LoyaltyState());
  }
}

ProviderContainer _container(FakeLoyaltyGateway fake) {
  return ProviderContainer(
    overrides: [loyaltyGatewayProvider.overrideWithValue(fake)],
  );
}

void main() {
  group('derivedTier', () {
    test('bronze below 2000', () {
      expect(derivedTier(0), Tier.bronze);
      expect(derivedTier(1999), Tier.bronze);
    });
    test('silver at 2000..4999', () {
      expect(derivedTier(2000), Tier.silver);
      expect(derivedTier(4999), Tier.silver);
    });
    test('gold at 5000+', () {
      expect(derivedTier(5000), Tier.gold);
      expect(derivedTier(99999), Tier.gold);
    });
  });

  group('LoyaltyState json round-trip', () {
    test('parses supabase row shape', () {
      final s = LoyaltyState.fromJson({
        'points': 120,
        'lifetime_points': 2100,
        'stamps': 7,
        'completed_cards': 2,
        'spinner_tokens': 1,
        'match_tokens': 0,
        'scratch_tokens': 3,
        'double_next_order': true,
        'vouchers': [
          {'type': 'free_drink', 'at': '2026-08-22T10:00:00Z'},
        ],
      });
      expect(s.tier, Tier.silver);
      expect(s.points, 120);
      expect(s.vouchers.single.type, VoucherType.freeDrink);
    });
    test('voucher toJson/fromJson round trip', () {
      final v = Voucher(type: VoucherType.freeTopping, grantedAt: DateTime.parse('2026-01-01T00:00:00Z'));
      expect(Voucher.fromJson(v.toJson()).type, VoucherType.freeTopping);
    });
  });

  group('LoyaltyController.refreshFor', () {
    test('loads server state and clears lastRefreshFailed', () async {
      final serverState = LoyaltyState(points: 50, stamps: 3, lifetimePoints: 500);
      final fake = FakeLoyaltyGateway(
        byGoogleUserId: {'g1': (phone: '+201000000001', state: serverState)},
      );
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier = container.read(loyaltyProvider.notifier);
      await notifier.refreshFor('g1');
      expect(container.read(loyaltyProvider).points, 50);
      expect(notifier.lastRefreshFailed, isFalse);
    });

    test('no row → zero state not failure', () async {
      final fake = FakeLoyaltyGateway();
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier = container.read(loyaltyProvider.notifier);
      // seed with non-zero to ensure it zeroes
      await notifier.grantPoints(10);
      await notifier.refreshFor('missing');
      expect(container.read(loyaltyProvider).points, 0);
      expect(notifier.lastRefreshFailed, isFalse);
    });

    test('network failure keeps last-known and sets flag', () async {
      final fake = FakeLoyaltyGateway(throwOnFetchState: true);
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier = container.read(loyaltyProvider.notifier);
      await notifier.grantPoints(20);
      expect(container.read(loyaltyProvider).points, 20);
      await notifier.refreshFor('g1');
      expect(container.read(loyaltyProvider).points, 20);
      expect(notifier.lastRefreshFailed, isTrue);
      // next success clears flag
      fake.throwOnFetchState = false;
      fake.byGoogleUserId['g1'] = (phone: '+201000000001', state: const LoyaltyState(points: 5));
      await notifier.refreshFor('g1');
      expect(notifier.lastRefreshFailed, isFalse);
      expect(container.read(loyaltyProvider).points, 5);
    });
  });

  group('LoyaltyController — server-authoritative preview (no client persist)', () {
    test('previewEarned: pickup 95 → 10 pts (round half-up) via pure rules', () async {
      final fake = FakeLoyaltyGateway();
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier = container.read(loyaltyProvider.notifier);
      expect(notifier.previewEarned(subtotalEgp: 95, dineIn: false), 10);
    });

    test('previewEarned respects dine-in multiplier and double window', () async {
      final fake = FakeLoyaltyGateway();
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier = container.read(loyaltyProvider.notifier);
      expect(notifier.previewEarned(subtotalEgp: 90, dineIn: true), 10);
      notifier.state = const LoyaltyState(doubleNextOrder: true);
      expect(notifier.previewEarned(subtotalEgp: 100, dineIn: false), 20);
    });

    test('no client persist — LoyaltyGateway has watchState not persist', () async {
      final notifier = _container(FakeLoyaltyGateway()).read(loyaltyProvider.notifier);
      expect(notifier, isA<LoyaltyController>());
      final fake = FakeLoyaltyGateway();
      expect(fake.watchState('+201000000001'), isA<Stream<LoyaltyState>>());
      // Server trigger owns crediting; client only refreshes via watch/refreshFor
    });

    test('previewRedeemable uses pure redeemable rules', () async {
      final fake = FakeLoyaltyGateway();
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier = container.read(loyaltyProvider.notifier);
      notifier.state = const LoyaltyState(points: 200);
      final redemption = notifier.previewRedeemable(hasDrinkLine: true);
      expect(redemption, isNotNull);
      expect(redemption!.type, RedemptionType.freeDrink);
    });
  });

  group('LoyaltyController token grants (local preview, no persist)', () {
    test('grantStamps pure wrap (local, no server persist)', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState()),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      container.read(loyaltyProvider.notifier).state = const LoyaltyState(stamps: 9);
      await container.read(loyaltyProvider.notifier).grantStamps(1);
      final s = container.read(loyaltyProvider);
      expect(s.stamps, 0);
      expect(s.completedCards, 1);
    });

    test('grantPoints adds both balances (local)', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState()),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      container.read(loyaltyProvider.notifier).state = const LoyaltyState(points: 10, lifetimePoints: 10);
      await container.read(loyaltyProvider.notifier).grantPoints(50);
      expect(container.read(loyaltyProvider).points, 60);
      expect(container.read(loyaltyProvider).lifetimePoints, 60);
    });

    test('consume token returns false when none (no persist)', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState(spinnerTokens: 0)),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      final ok = await container.read(loyaltyProvider.notifier).consumeSpinnerToken();
      expect(ok, isFalse);
    });
  });
}
