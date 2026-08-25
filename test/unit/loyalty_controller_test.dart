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
    this.throwOnPersist = false,
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
  bool throwOnPersist;
  int persistCalls = 0;
  String? lastPersistPhone;
  LoyaltyState? lastPersisted;

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
  Future<void> persist(String phone, LoyaltyState state) async {
    persistCalls++;
    lastPersistPhone = phone;
    lastPersisted = state;
    if (throwOnPersist) throw Exception('persist fail');
    stateByPhone[phone] = state;
    // keep byGoogleUserId in sync if exists
    for (final entry in byGoogleUserId.entries) {
      if (entry.value.phone == phone) {
        byGoogleUserId[entry.key] = (phone: phone, state: state);
      }
    }
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

  group('LoyaltyController.creditProcessedOrder', () {
    test('basic earn: pickup 95 → 10 pts (round half-up) and stamp when >=50', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState()),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier = container.read(loyaltyProvider.notifier);
      await notifier.creditProcessedOrder(orderId: 'o1', subtotalEgp: 95, dineIn: false);
      final s = container.read(loyaltyProvider);
      expect(s.points, 10);
      expect(s.lifetimePoints, 10);
      expect(s.stamps, 1);
      expect(s.processedOrders, contains('o1'));
      expect(fake.persistCalls, 1);
      expect(fake.lastPersistPhone, '+201000000001');
    });

    test('idempotency: same orderId twice does not double credit', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState()),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      final notifier = container.read(loyaltyProvider.notifier);
      await notifier.creditProcessedOrder(orderId: 'o1', subtotalEgp: 100, dineIn: false);
      expect(container.read(loyaltyProvider).points, 10);
      expect(fake.persistCalls, 1);
      // second call — should resync but not add points
      await notifier.creditProcessedOrder(orderId: 'o1', subtotalEgp: 100, dineIn: false);
      expect(container.read(loyaltyProvider).points, 10);
      expect(fake.persistCalls, 1);
      // processedOrders still single
      expect(container.read(loyaltyProvider).processedOrders.where((e) => e == 'o1').length, 1);
    });

    test('dine-in multiplier 1.1: 90 → 9.9 → 10 pts', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState()),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o1', subtotalEgp: 90, dineIn: true);
      expect(container.read(loyaltyProvider).points, 10);
    });

    test('double window doubles earn and consumes flag', () async {
      final fake = FakeLoyaltyGateway(
        currentUserId: 'g1',
        byGoogleUserId: {
          'g1': (phone: '+201000000001', state: const LoyaltyState(doubleNextOrder: true)),
        },
        config: const {},
      );
      final container = _container(fake);
      addTearDown(container.dispose);
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o1', subtotalEgp: 100, dineIn: false);
      final s = container.read(loyaltyProvider);
      expect(s.points, 20);
      expect(s.doubleNextOrder, isFalse);
      // next order without flag → not doubled (config not active)
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o2', subtotalEgp: 100, dineIn: false);
      expect(container.read(loyaltyProvider).points, 30);
    });

    test('server double_window_active via app_config also doubles', () async {
      final fake = FakeLoyaltyGateway(
        currentUserId: 'g1',
        byGoogleUserId: {
          'g1': (phone: '+201000000001', state: const LoyaltyState()),
        },
        config: {'double_window_active': true},
      );
      final container = _container(fake);
      addTearDown(container.dispose);
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o1', subtotalEgp: 100, dineIn: false);
      expect(container.read(loyaltyProvider).points, 20);
    });

    test('stamp wrap at 10 → completedCards+1, voucher, reset, spinner at 3', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: LoyaltyState(stamps: 9, spinnerTokens: 0, completedCards: 0)),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o1', subtotalEgp: 100, dineIn: false);
      final s = container.read(loyaltyProvider);
      expect(s.stamps, 0);
      expect(s.completedCards, 1);
      expect(s.vouchers.length, 1);
      expect(s.vouchers.single.type, VoucherType.freeSnack);
      // every 3rd stamp grants spinner: 2→3 should grant
      final fake2 = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState(stamps: 2)),
      });
      final c2 = _container(fake2);
      addTearDown(c2.dispose);
      await c2.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o1', subtotalEgp: 100, dineIn: false);
      expect(c2.read(loyaltyProvider).stamps, 3);
      expect(c2.read(loyaltyProvider).spinnerTokens, 1);
    });

    test('redemption deducts points before earn, lifetime only grows by earned', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState(points: 250, lifetimePoints: 1000)),
      }, config: {'stamp_min_spend': 50});
      final container = _container(fake);
      addTearDown(container.dispose);
      final redemption = Redemption(type: RedemptionType.freeDrink, costPts: 200);
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(
            orderId: 'o1',
            subtotalEgp: 100,
            dineIn: false,
            redemption: redemption,
          );
      final s = container.read(loyaltyProvider);
      // 250-200=50 +10 earned =60
      expect(s.points, 60);
      expect(s.lifetimePoints, 1010);
    });

    test('subtotal below stampMinSpend does not grant stamp', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState(stamps: 0)),
      }, config: {'stamp_min_spend': 50});
      final container = _container(fake);
      addTearDown(container.dispose);
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o1', subtotalEgp: 30, dineIn: false);
      expect(container.read(loyaltyProvider).stamps, 0);
      expect(container.read(loyaltyProvider).points, 3);
    });

    test('offline: persist failure still keeps optimistic state', () async {
      final fake = FakeLoyaltyGateway(
        currentUserId: 'g1',
        byGoogleUserId: {
          'g1': (phone: '+201000000001', state: const LoyaltyState(points: 0)),
        },
        throwOnPersist: true,
      );
      final container = _container(fake);
      addTearDown(container.dispose);
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o1', subtotalEgp: 100, dineIn: false);
      expect(container.read(loyaltyProvider).points, 10);
      expect(fake.persistCalls, 1);
    });

    test('guest (no uid) stays local-only, no persist', () async {
      final fake = FakeLoyaltyGateway(currentUserId: null);
      final container = _container(fake);
      addTearDown(container.dispose);
      await container.read(loyaltyProvider.notifier).creditProcessedOrder(orderId: 'o1', subtotalEgp: 100, dineIn: false);
      expect(container.read(loyaltyProvider).points, 10);
      expect(fake.persistCalls, 0);
    });
  });

  group('LoyaltyController token grants', () {
    test('grantStamps pure wrap and persist', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState()),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      // seed in-memory state directly (grantStamps uses optimistic local state, not server fetch)
      container.read(loyaltyProvider.notifier).state = const LoyaltyState(stamps: 9);
      await container.read(loyaltyProvider.notifier).grantStamps(1);
      final s = container.read(loyaltyProvider);
      expect(s.stamps, 0);
      expect(s.completedCards, 1);
      expect(fake.persistCalls, 1);
    });

    test('grantPoints adds both balances', () async {
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

    test('consume token returns false when none', () async {
      final fake = FakeLoyaltyGateway(currentUserId: 'g1', byGoogleUserId: {
        'g1': (phone: '+201000000001', state: const LoyaltyState(spinnerTokens: 0)),
      });
      final container = _container(fake);
      addTearDown(container.dispose);
      final ok = await container.read(loyaltyProvider.notifier).consumeSpinnerToken();
      expect(ok, isFalse);
      expect(fake.persistCalls, 0);
    });
  });
}
