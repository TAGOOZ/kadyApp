import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kady_app/data/repos/quest_state_store.dart';
import 'package:kady_app/domain/quests_engine.dart';

void main() {
  late QuestStateStore store;
  const phone = '+201000000001';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = QuestStateStore(prefs);
  });

  group('QuestStateStore.phoneHash', () {
    test('is stable hex', () {
      final h1 = QuestStateStore.phoneHash(phone);
      final h2 = QuestStateStore.phoneHash(phone);
      expect(h1, h2);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(h1), isTrue);
    });
    test('different phones differ', () {
      expect(QuestStateStore.phoneHash('+201000000001'), isNot(equals(QuestStateStore.phoneHash('+201000000002'))));
    });
  });

  group('claimedQuests', () {
    test('initially empty', () async {
      expect(await store.claimedQuests(phone), isEmpty);
    });
    test('markClaimed idempotent', () async {
      expect(await store.markClaimed(phone, QuestId.drinksVariety), isTrue);
      expect(await store.markClaimed(phone, QuestId.drinksVariety), isFalse);
      final claimed = await store.claimedQuests(phone);
      expect(claimed, contains(QuestId.drinksVariety));
      expect(claimed.length, 1);
    });
    test('different phones isolated', () async {
      await store.markClaimed(phone, QuestId.matchNight);
      expect(await store.claimedQuests('+201000000002'), isEmpty);
    });
  });

  group('badgesEarned', () {
    test('initially empty', () async {
      expect(await store.badgesEarned(phone), isEmpty);
    });
    test('markBadgeEarned once', () async {
      expect(await store.markBadgeEarned(phone, BadgeId.matchNightsClub), isTrue);
      expect(await store.markBadgeEarned(phone, BadgeId.matchNightsClub), isFalse);
      final badges = await store.badgesEarned(phone);
      expect(badges.containsKey(BadgeId.matchNightsClub), isTrue);
      expect(badges[BadgeId.matchNightsClub], isA<DateTime>());
    });
    test('multiple badges', () async {
      await store.markBadgeEarned(phone, BadgeId.matchNightsClub);
      await store.markBadgeEarned(phone, BadgeId.examWarrior);
      final badges = await store.badgesEarned(phone);
      expect(badges.length, 2);
    });
  });

  group('pendingGrants', () {
    test('initially empty', () async {
      expect(await store.pendingGrants(phone), isEmpty);
    });
    test('add and retrieve', () async {
      final grant = PendingGrant(type: 'match_token', n: 1, createdAtUtc: DateTime.parse('2026-01-01T00:00:00Z'));
      await store.addPendingGrant(phone, grant);
      final list = await store.pendingGrants(phone);
      expect(list.length, 1);
      expect(list.first.type, 'match_token');
      expect(list.first.n, 1);
    });
    test('multiple grants', () async {
      await store.addPendingGrant(phone, PendingGrant(type: 'stamp', n: 1, createdAtUtc: DateTime.utc(2026, 1, 1)));
      await store.addPendingGrant(phone, PendingGrant(type: 'match_token', n: 2, createdAtUtc: DateTime.utc(2026, 1, 2)));
      expect((await store.pendingGrants(phone)).length, 2);
    });
    test('isolated per phone', () async {
      await store.addPendingGrant(phone, PendingGrant(type: 'stamp', n: 1, createdAtUtc: DateTime.utc(2026, 1, 1)));
      expect(await store.pendingGrants('+201000000002'), isEmpty);
    });
    test('malformed json returns empty', () async {
      final prefs = await SharedPreferences.getInstance();
      final key = 'pending_grants.${QuestStateStore.phoneHash(phone)}';
      await prefs.setString(key, 'not-json');
      expect(await store.pendingGrants(phone), isEmpty);
    });
  });

  group('QuestFeedRepo helpers', () {
    test('applyMatchNightFlags tags orders correctly', () {
      final orders = [
        QuestOrderInput(orderId: 'o1', modeWire: 'dine_in', createdAtUtc: DateTime.utc(2026, 8, 20, 19), itemIds: ['tea']),
        QuestOrderInput(orderId: 'o2', modeWire: 'pickup', createdAtUtc: DateTime.utc(2026, 8, 21, 10), itemIds: ['snack']),
      ];
      final windows = [CampaignWindow(startsAtUtc: DateTime.utc(2026, 8, 20, 18), endsAtUtc: DateTime.utc(2026, 8, 20, 22))];
      final flagged = applyMatchNightFlags(orders, windows);
      expect(flagged[0].placedDuringMatchNight, isTrue);
      expect(flagged[1].placedDuringMatchNight, isFalse);
    });
    test('QuestSnapshot offline flag', () {
      const snap = QuestSnapshot(orders: [], itemCategories: {}, windows: CampaignWindows.empty, googleUserId: 'g1', offline: true);
      expect(snap.offline, isTrue);
    });
  });
}
