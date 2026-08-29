// Unit tests for the pure quests/badges engine (#010): month
// distinct-drink counting (duplicates collapse, non-drinks and
// cross-month orders excluded), Egypt Saturday-start week boundaries,
// both-modes partial→complete, match-night edge minutes and badge rules.
// No flutter bindings, no network.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/quest_state_store.dart';
import 'package:kady_app/domain/quests_engine.dart';

QuestOrderInput _order(
  String id,
  String mode,
  DateTime at, [
  List<String> itemIds = const [],
  bool matchNight = false,
]) =>
    QuestOrderInput(
      orderId: id,
      modeWire: mode,
      createdAtUtc: at,
      itemIds: itemIds,
      placedDuringMatchNight: matchNight,
    );

const _categories = {
  'latte': 'hot_drinks',
  'iced': 'cold_drinks',
  'tea': 'hot_drinks',
  'cake': 'snacks',
};

void main() {
  // 2026-08-20 is a Thursday; August 2026 month window; current Egypt
  // week runs Sat Aug 15 → Fri Aug 21.
  final now = DateTime(2026, 8, 20, 15);

  group('Q1 جرّب ٣ مشروبات مختلفة الشهر ده', () {
    test('distinct ids count once; non-drinks and cross-month excluded', () {
      final orders = [
        _order('o1', 'pickup', DateTime(2026, 8, 5), ['latte']),
        // Same drink again — collapses into one distinct id.
        _order('o2', 'dine_in', DateTime(2026, 8, 9), ['latte']),
        // Snacks never count.
        _order('o3', 'delivery', DateTime(2026, 8, 11), ['cake']),
        // July order — outside the Gregorian month window.
        _order('o4', 'pickup', DateTime(2026, 7, 30), ['iced', 'tea']),
      ];
      expect(
        evaluate(QuestId.drinksVariety,
            orders: orders, itemCategories: _categories, now: now),
        const QuestProgress(progress: 1, target: 3),
      );
    });

    test('reaches target with three distinct drinks', () {
      final orders = [
        _order('o1', 'pickup', DateTime(2026, 8, 5), ['latte', 'cake']),
        _order('o2', 'delivery', DateTime(2026, 8, 9), ['iced']),
        _order('o3', 'dine_in', DateTime(2026, 8, 18), ['tea', 'tea']),
      ];
      expect(
        evaluate(QuestId.drinksVariety,
            orders: orders, itemCategories: _categories, now: now),
        const QuestProgress(progress: 3, target: 3),
      );
    });

    test('unknown category slugs are ignored', () {
      final orders = [
        _order('o1', 'pickup', DateTime(2026, 8, 5), ['mystery-item']),
      ];
      expect(
        evaluate(QuestId.drinksVariety,
            orders: orders, itemCategories: _categories, now: now),
        const QuestProgress(progress: 0, target: 3),
      );
    });

    test('iced-espresso counts as drink (0005)', () {
      const icedCats = {'icedLatte': 'iced-espresso'};
      final orders = [_order('o1', 'pickup', DateTime(2026, 8, 5), ['icedLatte'])];
      expect(
        evaluate(QuestId.drinksVariety,
            orders: orders, itemCategories: icedCats, now: now),
        const QuestProgress(progress: 1, target: 3),
      );
    });
  });

  group('Q2 اطلب خلال ليلة الماتش', () {
    test('flagged order this month completes it', () {
      final orders = [
        _order('o1', 'dine_in', DateTime(2026, 8, 10), const [], true),
      ];
      expect(
        evaluate(QuestId.matchNight,
            orders: orders, itemCategories: _categories, now: now),
        const QuestProgress(progress: 1, target: 1),
      );
    });

    test('flagged order last month does not carry over', () {
      final orders = [
        _order('o1', 'dine_in', DateTime(2026, 7, 28), const [], true),
      ];
      expect(
        evaluate(QuestId.matchNight,
            orders: orders, itemCategories: _categories, now: now),
        const QuestProgress(progress: 0, target: 1),
      );
    });
  });

  group('Q3 طلب توصيل وطلب استلام الأسبوع ده (Sat-start week)', () {
    test('partial then complete across the week', () {
      // Pickup only → half way.
      final partial = [
        _order('o1', 'pickup', DateTime(2026, 8, 17)), // Monday
      ];
      expect(
        evaluate(QuestId.bothModes,
            orders: partial, itemCategories: _categories, now: now),
        const QuestProgress(progress: 1, target: 2),
      );

      // Add a delivery inside the same week → complete.
      final complete = [
        ...partial,
        _order('o2', 'delivery', DateTime(2026, 8, 15, 10)), // Saturday
      ];
      expect(
        evaluate(QuestId.bothModes,
            orders: complete, itemCategories: _categories, now: now),
        const QuestProgress(progress: 2, target: 2),
      );
    });

    test('Friday of LAST week is excluded; Saturday 00:00 starts the week',
        () {
      final orders = [
        // Last week's Friday — one day before the current week opens.
        _order('old-delivery', 'delivery', DateTime(2026, 8, 14, 23)),
        // Exactly at the week's first instant — inclusive.
        _order('sat-pickup', 'pickup', DateTime(2026, 8, 15)),
      ];
      expect(
        evaluate(QuestId.bothModes,
            orders: orders, itemCategories: _categories, now: now),
        const QuestProgress(progress: 1, target: 2),
      );
    });

    test('weekStartSaturday maps Saturday onto itself and Sunday back one day',
        () {
      final saturday = weekStartSaturday(DateTime(2026, 8, 15, 9));
      expect(saturday, DateTime(2026, 8, 15));
      final sundayStart = weekStartSaturday(DateTime(2026, 8, 16, 1));
      expect(sundayStart, DateTime(2026, 8, 15));
    });

    test('month helpers normalize year rollover', () {
      expect(monthStartOf(now), DateTime(2026, 8, 1));
      expect(lastDayOfMonthOf(now), 31);
      expect(lastDayOfMonthOf(DateTime(2026, 12, 5)), 31);
      expect(monthStartOf(DateTime(2027, 1, 2)), DateTime(2027, 1, 1));
    });
  });

  group('match-night window tagging', () {
    final window = CampaignWindow(
      startsAtUtc: DateTime(2026, 8, 10, 20),
      endsAtUtc: DateTime(2026, 8, 10, 23),
    );

    test('edge minutes are inclusive', () {
      expect(window.contains(DateTime(2026, 8, 10, 20)), isTrue);
      expect(window.contains(DateTime(2026, 8, 10, 23)), isTrue);
      expect(window.contains(DateTime(2026, 8, 10, 19, 59)), isFalse);
      expect(window.contains(DateTime(2026, 8, 10, 23, 0, 1)), isFalse);
    });

    test('applyMatchNightFlags tags only orders inside active windows', () {
      final orders = [
        _order('inside', 'pickup', DateTime(2026, 8, 10, 21)),
        _order('before', 'pickup', DateTime(2026, 8, 10, 19)),
        _order('after', 'pickup', DateTime(2026, 8, 11)),
      ];
      final tagged = applyMatchNightFlags(orders, [window]);
      expect(tagged.where((o) => o.placedDuringMatchNight).map((o) => o.orderId),
          ['inside']);
    });
  });

  group('badges', () {
    test('first-ever match-night order earns نادي ليالي الماتشات', () {
      final orders = [
        _order('o1', 'pickup', DateTime(2025, 3, 2), const [], true),
      ];
      final earned = evaluateBadges(
        orders: orders,
        windows: CampaignWindows.empty,
        reachedGoldTier: false,
      );
      expect(earned, {BadgeId.matchNightsClub});
    });

    test('exam/ramadan windows earn their badges by order placement', () {
      final windows = CampaignWindows(
        examSeason: [
          CampaignWindow(
            startsAtUtc: DateTime(2026, 1, 10),
            endsAtUtc: DateTime(2026, 2, 5),
          ),
        ],
        ramadan: [
          CampaignWindow(
            startsAtUtc: DateTime(2026, 2, 18),
            endsAtUtc: DateTime(2026, 3, 19),
          ),
        ],
      );
      final earned = evaluateBadges(
        orders: [
          _order('exam-order', 'pickup', DateTime(2026, 1, 15)),
          _order('ramadan-order', 'delivery', DateTime(2026, 3, 1)),
          _order('plain-order', 'dine_in', DateTime(2026, 8, 2)),
        ],
        windows: windows,
        reachedGoldTier: false,
      );
      expect(earned, {BadgeId.examWarrior, BadgeId.ramadanOwl});
    });

    test('عميل ذهبي gates on the caller-computed tier', () {
      expect(
        evaluateBadges(
            orders: const [], windows: CampaignWindows.empty, reachedGoldTier: false),
        isEmpty,
      );
      expect(
        evaluateBadges(
            orders: const [], windows: CampaignWindows.empty, reachedGoldTier: true),
        {BadgeId.goldLoyalist},
      );
    });
  });

  group('quest catalog', () {
    test('targets/rewards match slice spec', () {
      expect(questCatalog.length, 3);
      expect(questDefOf(QuestId.drinksVariety).target, 3);
      expect(questDefOf(QuestId.drinksVariety).reward, QuestReward.bonusPoints);
      expect(questDefOf(QuestId.matchNight).reward, QuestReward.matchToken);
      expect(questDefOf(QuestId.matchNight).endsThisWeek, isFalse);
      expect(questDefOf(QuestId.bothModes).target, 2);
      expect(questDefOf(QuestId.bothModes).reward, QuestReward.bonusStamp);
      expect(questDefOf(QuestId.bothModes).endsThisWeek, isTrue);
    });

    test('progress equality works for test assertions', () {
      expect(const QuestProgress(progress: 2, target: 3).complete, isFalse);
      expect(const QuestProgress(progress: 3, target: 3).complete, isTrue);
      expect(const QuestProgress(progress: 2, target: 3),
          const QuestProgress(progress: 2, target: 3));
    });
  });
}
