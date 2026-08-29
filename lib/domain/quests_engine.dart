// Quests & badges pure engine (issue #010, FEATURES §5.4–5.5).
//
// Pure Dart only — no flutter/supabase imports — so the whole catalog,
// window math and badge rules are unit-testable without a device.
// Callers feed completed orders as [QuestOrderInput] records plus the
// menu `{itemId → categorySlug}` map and `now`; progress is always
// recomputed from order history (single source of truth), never stored
// counters where derivable (issue #010 acceptance).
library;

/// Quest identifiers for slice #010's launch catalog.
enum QuestId { drinksVariety, matchNight, bothModes }

/// Reward granted when a quest claim is accepted.
///
/// `bonusPoints` credits straight through the loyalty seam
/// (`grantPoints`). `matchToken`/`bonusStamp` have NO controller grant
/// method in #007's shared seam yet — those claims are queued as
/// pending grants by the UI layer (documented deviation).
enum QuestReward { bonusPoints, matchToken, bonusStamp }

/// One completed order flattened to what quest math needs.
class QuestOrderInput {
  const QuestOrderInput({
    required this.orderId,
    required this.modeWire,
    required this.createdAtUtc,
    required this.itemIds,
    this.placedDuringMatchNight = false,
  });

  final String orderId;

  /// Raw `orders.mode` wire value (`dine_in`/`pickup`/`delivery`).
  final String modeWire;
  final DateTime createdAtUtc;
  final List<String> itemIds;

  /// Precomputed flag: order landed inside an active match-night
  /// campaign window (see `applyMatchNightFlags` in the data layer).
  final bool placedDuringMatchNight;

  @override
  bool operator ==(Object other) =>
      other is QuestOrderInput && other.orderId == orderId;

  @override
  int get hashCode => orderId.hashCode;
}

/// Half-open-instant campaign window `[startsAt, endsAt]` — inclusive on
/// both edges so orders placed exactly at window boundaries count
/// (edge-minute acceptance criterion).
class CampaignWindow {
  const CampaignWindow({required this.startsAtUtc, required this.endsAtUtc});

  final DateTime startsAtUtc;
  final DateTime endsAtUtc;

  bool contains(DateTime at) =>
      !at.isBefore(startsAtUtc) && !at.isAfter(endsAtUtc);

  @override
  bool operator ==(Object other) =>
      other is CampaignWindow &&
      other.startsAtUtc == startsAtUtc &&
      other.endsAtUtc == endsAtUtc;

  @override
  int get hashCode => Object.hash(startsAtUtc, endsAtUtc);
}

/// Active windows per campaign kind, fetched once per session by the
/// data layer; empty lists mean "campaign off / offline".
class CampaignWindows {
  const CampaignWindows({
    this.matchNight = const [],
    this.examSeason = const [],
    this.ramadan = const [],
  });

  final List<CampaignWindow> matchNight;
  final List<CampaignWindow> examSeason;
  final List<CampaignWindow> ramadan;

  static const empty = CampaignWindows();
}

/// Immutable progress snapshot for one quest.
class QuestProgress {
  const QuestProgress({required this.progress, required this.target})
      : complete = progress >= target;

  final int progress;
  final int target;
  final bool complete;

  @override
  bool operator ==(Object other) =>
      other is QuestProgress &&
      other.progress == progress &&
      other.target == target &&
      other.complete == complete;

  @override
  int get hashCode => Object.hash(progress, target, complete);

  @override
  String toString() => 'QuestProgress($progress/$target)';
}

/// Static quest catalog entry (titles/deadline labels live here so both
/// languages ship with the engine; icons are a UI concern).
class QuestDef {
  const QuestDef({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.target,
    required this.reward,
    required this.deadlineLabelAr,
    required this.deadlineLabelEn,
    required this.endsThisWeek,
  });

  final QuestId id;
  final String titleAr;
  final String titleEn;
  final int target;
  final QuestReward reward;

  /// نهاية الشهر / نهاية الأسبوع chip label.
  final String deadlineLabelAr;
  final String deadlineLabelEn;

  /// True → period ends Friday (Egypt week starts Saturday); false →
  /// period ends with the Gregorian month.
  final bool endsThisWeek;
}

const questCatalog = <QuestDef>[
  QuestDef(
    id: QuestId.drinksVariety,
    titleAr: 'جرّب ٣ مشروبات مختلفة الشهر ده',
    titleEn: 'Try 3 different drinks this month',
    target: 3,
    reward: QuestReward.bonusPoints,
    deadlineLabelAr: 'نهاية الشهر',
    deadlineLabelEn: 'Ends this month',
    endsThisWeek: false,
  ),
  QuestDef(
    id: QuestId.matchNight,
    titleAr: 'اطلب خلال ليلة الماتش',
    titleEn: 'Order during a match night',
    target: 1,
    reward: QuestReward.matchToken,
    deadlineLabelAr: 'نهاية الشهر',
    deadlineLabelEn: 'Ends this month',
    endsThisWeek: false,
  ),
  QuestDef(
    id: QuestId.bothModes,
    titleAr: 'طلب توصيل وطلب استلام الأسبوع ده',
    titleEn: 'One delivery + one pickup this week',
    target: 2,
    reward: QuestReward.bonusStamp,
    deadlineLabelAr: 'نهاية الأسبوع',
    deadlineLabelEn: 'Ends this week',
    endsThisWeek: true,
  ),
];

QuestDef questDefOf(QuestId id) =>
    questCatalog.firstWhere((def) => def.id == id);

/// Menu category slugs that count as drinks for Q1.
/// Keep in sync with `loyalty_rules.dart:isDrinkCategorySlug` and SQL
/// intake pipeline (`hot_drinks`, `cold_drinks`, `iced-espresso`).
const drinkCategorySlugs = {
  'hot_drinks',
  'cold_drinks',
  'iced-espresso',
  'hot-drinks',
  'cold-drinks',
};

// ---------------------------------------------------------------------------
// Period math (local wall-clock; Egypt weeks start Saturday)
// ---------------------------------------------------------------------------

/// Current Gregorian month as an inclusive instant range:
/// first day 00:00 (inclusive) → first day of next month (exclusive edge
/// handled via `isBefore`).
DateTime monthStartOf(DateTime now) => DateTime(now.year, now.month);

DateTime monthEndInstantOf(DateTime now) => DateTime(now.year, now.month + 1);

/// Start of the Egypt week containing [now]: most recent Saturday 00:00
/// local time (a Saturday maps onto itself).
DateTime weekStartSaturday(DateTime now) {
  final offset = (now.weekday - DateTime.saturday) % DateTime.daysPerWeek;
  final daysBack = offset < 0 ? offset + DateTime.daysPerWeek : offset;
  final day = DateTime(now.year, now.month, now.day - daysBack);
  return day;
}

/// Exclusive end of the Egypt week: the Saturday after the current one,
/// i.e. Friday 24:00.
DateTime weekEndInstantSaturday(DateTime now) =>
    weekStartSaturday(now).add(const Duration(days: DateTime.daysPerWeek));

/// Last calendar day of [now]'s month (for the `٣١/٨`-style deadline chip).
int lastDayOfMonthOf(DateTime now) {
  final nextMonth = DateTime(now.year, now.month + 1);
  return nextMonth.subtract(const Duration(days: 1)).day;
}

bool _inRange(DateTime at, DateTime startInclusive, DateTime endExclusive) =>
    !at.isBefore(startInclusive) && at.isBefore(endExclusive);

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

/// Recomputes progress for one quest from full completed-order history.
///
/// Contract: [orders] contains COMPLETED (non-cancelled) orders only —
/// the data layer filters `status = 'done'` server-side.
QuestProgress evaluate(
  QuestId id, {
  required List<QuestOrderInput> orders,
  required Map<String, String> itemCategories,
  required DateTime now,
}) {
  switch (id) {
    case QuestId.drinksVariety:
      final monthStart = monthStartOf(now);
      final monthEnd = monthEndInstantOf(now);
      final distinctDrinks = <String>{};
      for (final order in orders) {
        if (!_inRange(order.createdAtUtc, monthStart, monthEnd)) continue;
        for (final itemId in order.itemIds) {
          if (drinkCategorySlugs.contains(itemCategories[itemId])) {
            distinctDrinks.add(itemId);
          }
        }
      }
      return QuestProgress(progress: distinctDrinks.length, target: 3);

    case QuestId.matchNight:
      final monthStart = monthStartOf(now);
      final monthEnd = monthEndInstantOf(now);
      var hits = 0;
      for (final order in orders) {
        if (!_inRange(order.createdAtUtc, monthStart, monthEnd)) continue;
        if (order.placedDuringMatchNight) hits++;
      }
      return QuestProgress(progress: hits, target: 1);

    case QuestId.bothModes:
      final weekStart = weekStartSaturday(now);
      final weekEnd = weekEndInstantSaturday(now);
      final modes = <String>{
        for (final order in orders)
          if (_inRange(order.createdAtUtc, weekStart, weekEnd))
            order.modeWire,
      };
      var covered = 0;
      if (modes.contains('pickup')) covered++;
      if (modes.contains('delivery')) covered++;
      return QuestProgress(progress: covered, target: 2);
  }
}

// ---------------------------------------------------------------------------
// Badges
// ---------------------------------------------------------------------------

enum BadgeId { matchNightsClub, examWarrior, ramadanOwl, goldLoyalist }

/// Badge rules evaluated in the same pass as quests (issue #010):
/// - نادي ليالي الماتشات: FIRST match-night order ever (no time bound).
/// - رياضي الامتحانات: any order inside an active exam_season window.
/// - بومة رمضان: any order inside an active ramadan window.
/// - عميل ذهبي: caller passes whether loyalty tier reached gold
///   (`lifetimePoints ≥ 5000` via the shared loyalty seam).
Set<BadgeId> evaluateBadges({
  required List<QuestOrderInput> orders,
  required CampaignWindows windows,
  required bool reachedGoldTier,
}) {
  return {
    if (orders.any((o) => o.placedDuringMatchNight))
      BadgeId.matchNightsClub,
    if (orders.any((o) =>
        windows.examSeason.any((w) => w.contains(o.createdAtUtc))))
      BadgeId.examWarrior,
    if (orders.any((o) => windows.ramadan.any((w) => w.contains(o.createdAtUtc))))
      BadgeId.ramadanOwl,
    if (reachedGoldTier) BadgeId.goldLoyalist,
  };
}
