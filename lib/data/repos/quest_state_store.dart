// Quests & badges slice data layer (#010): two halves —
//
// 1. [QuestStateStore] — SharedPreferences persistence of claimed quests,
//    earned badges and the pending-grants queue, keyed by phone hash
//    (`quest.<phoneHash>.claimed.<questId>`, `badges.<phoneHash>.<badgeId>`).
// 2. [QuestFeedRepo] — read-only feed that flattens completed orders,
//    the menu item→category map and active campaign windows into
//    [QuestOrderInput]s for the pure engine. Own queries (the #006 repo's
//    `CustomerOrder` drops item ids); sits BESIDE order/menu repos,
//    never inside them.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/auth_controller.dart';
import '../../domain/quests_engine.dart';

// ---------------------------------------------------------------------------
// Pending grants — deviation queue for rewards outside the #007 seam
// ---------------------------------------------------------------------------

/// A reward the loyalty controller cannot grant yet (no `grantTokens()` /
/// stamp-grant method in the shared seam at slice time). Queued locally so
/// the owner can drain it once the seam grows; surfaced honestly in the UI
/// ("يُضاف تلقائيًا قريبًا").
class PendingGrant {
  const PendingGrant({
    required this.type,
    required this.n,
    required this.createdAtUtc,
  });

  /// 'match_token' | 'stamp'
  final String type;
  final int n;
  final DateTime createdAtUtc;

  Map<String, dynamic> toJson() => {
        'type': type,
        'n': n,
        'at': createdAtUtc.toIso8601String(),
      };

  static PendingGrant fromJson(Map<String, dynamic> j) => PendingGrant(
        type: j['type'] as String,
        n: (j['n'] as num).toInt(),
        createdAtUtc: DateTime.parse(j['at'] as String),
      );
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

class QuestStateStore {
  QuestStateStore(this._prefs);

  final SharedPreferences _prefs;

  /// No crypto dep per slice budget: stable-enough local obfuscation key.
  static String phoneHash(String phone) => phone.hashCode.toRadixString(16);

  String _claimedKey(String phoneHash, QuestId id) =>
      'quest.$phoneHash.claimed.${id.name}';
  String _badgeKey(String phoneHash, BadgeId id) =>
      'badges.$phoneHash.${id.name}';
  String _pendingKey(String phoneHash) => 'pending_grants.$phoneHash';

  Future<Set<QuestId>> claimedQuests(String phone) async {
    final hash = phoneHash(phone);
    return {
      for (final id in QuestId.values)
        if (_prefs.getBool(_claimedKey(hash, id)) ?? false) id,
    };
  }

  /// Marks a quest claimed; returns false if it was already claimed
  /// (idempotent double-claim guard).
  Future<bool> markClaimed(String phone, QuestId id) async {
    final key = _claimedKey(phoneHash(phone), id);
    if (_prefs.getBool(key) ?? false) return false;
    await _prefs.setBool(key, true);
    return true;
  }

  Future<Map<BadgeId, DateTime>> badgesEarned(String phone) async {
    final hash = phoneHash(phone);
    final earned = <BadgeId, DateTime>{};
    for (final id in BadgeId.values) {
      final raw = _prefs.getString(_badgeKey(hash, id));
      if (raw != null) earned[id] = DateTime.parse(raw);
    }
    return earned;
  }

  /// Persists an earned badge timestamp; returns true only when newly
  /// earned (drives the one-time celebration banner).
  Future<bool> markBadgeEarned(String phone, BadgeId id) async {
    final key = _badgeKey(phoneHash(phone), id);
    if (_prefs.getString(key) != null) return false;
    await _prefs.setString(key, DateTime.now().toUtc().toIso8601String());
    return true;
  }

  Future<List<PendingGrant>> pendingGrants(String phone) async {
    final raw = _prefs.getString(_pendingKey(phoneHash(phone)));
    if (raw == null) return const [];
    try {
      return [
        for (final entry in jsonDecode(raw) as List)
          PendingGrant.fromJson(Map<String, dynamic>.from(entry as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> addPendingGrant(String phone, PendingGrant grant) async {
    final current = [...await pendingGrants(phone), grant];
    await _prefs.setString(
      _pendingKey(phoneHash(phone)),
      jsonEncode([for (final g in current) g.toJson()]),
    );
  }
}

final questStoreProvider = FutureProvider<QuestStateStore>(
  (ref) async => QuestStateStore(await SharedPreferences.getInstance()),
);

// ---------------------------------------------------------------------------
// Feed seam + Supabase implementation
// ---------------------------------------------------------------------------

/// Flattened snapshot consumed by the screen/engine pass.
class QuestSnapshot {
  const QuestSnapshot({
    required this.orders,
    required this.itemCategories,
    required this.windows,
    required this.googleUserId,
    this.offline = false,
  });

  final List<QuestOrderInput> orders;
  final Map<String, String> itemCategories;
  final CampaignWindows windows;
  final String googleUserId;

  /// True when the campaign-window fetch failed (offline policy:
  /// windows empty → match-night quests/badges stay dormant, orders list
  /// still renders).
  final bool offline;
}

abstract class QuestFeedRepo {
  Future<List<QuestOrderInput>> fetchCompletedOrders(String googleUserId);

  /// `{menuItemId → categorySlug}` for Q1 drink filtering.
  Future<Map<String, String>> fetchItemCategories();

  /// Active windows for match_night / exam_season / ramadan, fetched once.
  /// Throws on network failure so callers can apply offline policy.
  Future<CampaignWindows> fetchCampaignWindows();
}

class SupabaseQuestFeed implements QuestFeedRepo {
  SupabaseQuestFeed(this._client);

  final SupabaseClient _client;

  @override
  Future<List<QuestOrderInput>> fetchCompletedOrders(String googleUserId) async {
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1)
        .toUtc()
        .toIso8601String();
    final rows = await _client //
        .from('orders')
        .select('id, mode, created_at, items')
        .eq('google_user_id', googleUserId)
        .eq('status', 'done')
        .gte('created_at', monthStart)
        .order('created_at', ascending: false)
        .limit(100);
    return [
      for (final row in List<Map<String, dynamic>>.from(rows as List))
        QuestOrderInput(
          orderId: row['id'] as String,
          modeWire: row['mode'] as String? ?? '',
          createdAtUtc: DateTime.parse(row['created_at'] as String),
          itemIds: [
            for (final item in (row['items'] as List?) ?? [])
              if (item is Map && item['id'] is String) item['id'] as String,
          ],
        ),
    ];
  }

  @override
  Future<Map<String, String>> fetchItemCategories() async {
    final rows = await _client //
        .from('menu_items')
        .select('id, menu_categories(slug)');
    final map = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(rows as List)) {
      final slug =
          (row['menu_categories'] as Map?)?['slug'] as String?;
      final id = row['id'] as String?;
      if (slug != null && id != null) map[id] = slug;
    }
    return map;
  }

  @override
  Future<CampaignWindows> fetchCampaignWindows() async {
    final rows = await _client //
        .from('campaigns')
        .select('kind, starts_at, ends_at')
        .eq('active', true);
    final matchNight = <CampaignWindow>[];
    final examSeason = <CampaignWindow>[];
    final ramadan = <CampaignWindow>[];
    for (final row in List<Map<String, dynamic>>.from(rows as List)) {
      final startsRaw = row['starts_at'];
      final endsRaw = row['ends_at'];
      if (startsRaw is! String || endsRaw is! String) continue;
      final window = CampaignWindow(
        startsAtUtc: DateTime.parse(startsRaw),
        endsAtUtc: DateTime.parse(endsRaw),
      );
      switch (row['kind'] as String?) {
        case 'match_night':
          matchNight.add(window);
        case 'exam_season':
          examSeason.add(window);
        case 'ramadan':
          ramadan.add(window);
      }
    }
    return CampaignWindows(
      matchNight: matchNight,
      examSeason: examSeason,
      ramadan: ramadan,
    );
  }
}

final questFeedProvider = Provider<QuestFeedRepo>(
  (ref) => SupabaseQuestFeed(supabase),
);

/// Tags each completed order with the match-night flag from the fetched
/// windows (inclusive edges — see [CampaignWindow.contains]).
List<QuestOrderInput> applyMatchNightFlags(
  List<QuestOrderInput> orders,
  List<CampaignWindow> matchWindows,
) =>
    [
      for (final order in orders)
        matchWindows.any((w) => w.contains(order.createdAtUtc))
            ? QuestOrderInput(
                orderId: order.orderId,
                modeWire: order.modeWire,
                createdAtUtc: order.createdAtUtc,
                itemIds: order.itemIds,
                placedDuringMatchNight: true,
              )
            : order,
    ];

/// One-shot combined fetch (orders + menu map + windows). Guests resolve to
/// an empty-order snapshot; any feed failure surfaces as AsyncError so the
/// screen shows its retry state. Pull-to-refresh invalidates this provider.
final questSnapshotProvider = FutureProvider.autoDispose<QuestSnapshot>(
  (ref) async {
    final feed = ref.watch(questFeedProvider);
    final googleUserId =
        ref.watch(authControllerProvider).googleUser?.id ?? '';
    CampaignWindows windows;
    var offline = false;
    try {
      windows = await feed.fetchCampaignWindows();
    } catch (_) {
      windows = CampaignWindows.empty;
      offline = true;
    }
    try {
      final results = await Future.wait([
        feed.fetchCompletedOrders(googleUserId),
        feed.fetchItemCategories(),
      ]);
      final orders = results[0] as List<QuestOrderInput>;
      final categories = results[1] as Map<String, String>;
      return QuestSnapshot(
        orders: applyMatchNightFlags(orders, windows.matchNight),
        itemCategories: categories,
        windows: windows,
        googleUserId: googleUserId,
        offline: offline,
      );
    } catch (_) {
      rethrow;
    }
  },
);
