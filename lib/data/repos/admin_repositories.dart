// Admin repositories (#015): campaigns / menu CRUD / app_config rules / KPI
// aggregates over a single low-level [AdminDbClient] seam so unit tests can
// fake the database without Supabase.
//
// Error policy: reads degrade to empty data on ordinary failures but RE-THROW
// [AdminAccessDeniedException] (Postgres 42501 — RLS denies non-admin writes)
// so the dashboard can show its lock panel. Mutations never swallow errors —
// the UI rolls back optimistic state on any failure.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';

// ---------------------------------------------------------------------------
// Db seam
// ---------------------------------------------------------------------------

/// Thrown when RLS denies the caller (Postgres `42501`
/// insufficient_privilege) — the admin lock-panel signal.
class AdminAccessDeniedException implements Exception {
  const AdminAccessDeniedException();

  @override
  String toString() => 'AdminAccessDeniedException';
}

bool isAccessDenied(Object error) {
  if (error is AdminAccessDeniedException) return true;
  if (error is PostgrestException) return error.code == '42501';
  return false;
}

/// Minimal PostgREST surface the admin dashboard needs. One interface keeps
/// every repository testable against an in-memory fake.
abstract interface class AdminDbClient {
  /// SELECT [columns] (may embed PostgREST joins like
  /// `*, menu_categories(...)`) with eq filters, one gte range filter,
  /// ordering and limit.
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    List<({String column, Object value})> eq = const [],
    ({String column, Object value})? gte,
    String? orderBy,
    bool ascending = true,
    int? limit,
  });

  Future<void> insert(String table, Map<String, dynamic> values);

  Future<void> update(
    String table,
    Map<String, dynamic> values, {
    required String whereColumn,
    required Object whereValue,
  });

  Future<void> upsert(
    String table,
    Map<String, dynamic> values, {
    String onConflict = 'id',
  });

  Future<void> delete(
    String table, {
    required String whereColumn,
    required Object whereValue,
  });
}

class SupabaseAdminDb implements AdminDbClient {
  const SupabaseAdminDb(this._client);

  final SupabaseClient _client;

  Never _mapError(Object e) {
    if (isAccessDenied(e)) throw const AdminAccessDeniedException();
    throw e;
  }

  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    List<({String column, Object value})> eq = const [],
    ({String column, Object value})? gte,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    try {
      var filtered = _client.from(table).select(columns);
      for (final f in eq) {
        filtered = filtered.eq(f.column, f.value);
      }
      if (gte != null) {
        filtered = filtered.gte(gte.column, gte.value);
      }
      final Object rows;
      if (orderBy == null && limit == null) {
        rows = await filtered;
      } else {
        var transformed = orderBy == null
            ? filtered
            : filtered.order(orderBy, ascending: ascending);
        if (limit != null) transformed = transformed.limit(limit);
        rows = await transformed;
      }
      return [
        for (final row in (rows as List).cast<Map>())
          Map<String, dynamic>.from(row),
      ];
    } catch (e) {
      _mapError(e);
    }
  }

  @override
  Future<void> insert(String table, Map<String, dynamic> values) async {
    try {
      await _client.from(table).insert(values);
    } catch (e) {
      _mapError(e);
    }
  }

  @override
  Future<void> update(
    String table,
    Map<String, dynamic> values, {
    required String whereColumn,
    required Object whereValue,
  }) async {
    try {
      await _client.from(table).update(values).eq(whereColumn, whereValue);
    } catch (e) {
      _mapError(e);
    }
  }

  @override
  Future<void> upsert(
    String table,
    Map<String, dynamic> values, {
    String onConflict = 'id',
  }) async {
    try {
      await _client.from(table).upsert(values, onConflict: onConflict);
    } catch (e) {
      _mapError(e);
    }
  }

  @override
  Future<void> delete(
    String table, {
    required String whereColumn,
    required Object whereValue,
  }) async {
    try {
      await _client.from(table).delete().eq(whereColumn, whereValue);
    } catch (e) {
      _mapError(e);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared plumbing
// ---------------------------------------------------------------------------

DateTime? parseAdminTimestamp(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}

Future<List<Map<String, dynamic>>> _readOrEmpty(
  Future<List<Map<String, dynamic>>> Function() op,
) async {
  try {
    return await op();
  } on AdminAccessDeniedException {
    rethrow;
  } catch (_) {
    return const [];
  }
}

// ---------------------------------------------------------------------------
// Campaigns
// ---------------------------------------------------------------------------

class Campaign {
  const Campaign({
    required this.id,
    required this.kind,
    required this.active,
    this.nameAr,
    this.startsAt,
    this.endsAt,
  });

  final String id;

  /// Wire vocabulary: double_points | match_night | exam_season | ramadan.
  final String kind;
  final bool active;
  final String? nameAr;
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory Campaign.fromRow(Map<String, dynamic> row) => Campaign(
        id: row['id'] as String,
        kind: (row['kind'] as String?) ?? '',
        active: (row['active'] as bool?) ?? false,
        nameAr: row['name_ar'] as String?,
        startsAt: parseAdminTimestamp(row['starts_at']),
        endsAt: parseAdminTimestamp(row['ends_at']),
      );

  /// `campaigns.kind` seed vocabulary (0001_init.sql §10).
  static const kinds = [
    'double_points',
    'match_night',
    'exam_season',
    'ramadan',
  ];
}

class CampaignRepository {
  const CampaignRepository(this._db);

  final AdminDbClient _db;

  /// All campaigns ordered by kind (table has no created_at column).
  Future<List<Campaign>> listAll() async {
    final rows = await _readOrEmpty(
      () => _db.select('campaigns', orderBy: 'kind'),
    );
    return [for (final row in rows) Campaign.fromRow(row)];
  }

  /// Flips [active] on one campaign. An activated/deactivated
  /// double_points campaign also flips the `double_window_active`
  /// app_config flag so new orders earn doubled points immediately.
  Future<void> toggleActive(Campaign campaign, bool active) async {
    await _db.update(
      'campaigns',
      {'active': active},
      whereColumn: 'id',
      whereValue: campaign.id,
    );
    if (campaign.kind == 'double_points') {
      await setDoubleWindowFlag(active);
    }
  }

  Future<void> setDoubleWindowFlag(bool active) async {
    await _db.upsert(
      'app_config',
      {'key': 'double_window_active', 'value': active},
      onConflict: 'key',
    );
  }

  Future<void> create({
    required String kind,
    required String nameAr,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    await _db.insert('campaigns', {
      'kind': kind,
      'name_ar': nameAr,
      if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
      if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
    });
  }

  Future<void> updateDates(
    String id, {
    required String kind,
    required String nameAr,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    await _db.update(
      'campaigns',
      {
        'kind': kind,
        'name_ar': nameAr,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
      },
      whereColumn: 'id',
      whereValue: id,
    );
  }
}

// ---------------------------------------------------------------------------
// Menu editor
// ---------------------------------------------------------------------------

class AdminCategory {
  const AdminCategory({
    required this.id,
    required this.slug,
    required this.nameAr,
    required this.nameEn,
  });

  final int id;
  final String slug;
  final String nameAr;
  final String nameEn;
}

/// Editable mirror of a `menu_items` row (joined category).
class AdminMenuItem {
  const AdminMenuItem({
    required this.id,
    required this.slug,
    required this.nameAr,
    required this.nameEn,
    required this.descAr,
    required this.descEn,
    required this.priceEgp,
    required this.isAvailable,
    required this.sort,
    this.categoryId,
    this.categorySlug,
    this.categoryNameAr,
  });

  final String id;
  final String slug;
  final String nameAr;
  final String nameEn;
  final String descAr;
  final String descEn;
  final int priceEgp;
  final bool isAvailable;
  final int sort;
  final int? categoryId;
  final String? categorySlug;
  final String? categoryNameAr;

  factory AdminMenuItem.fromRow(Map<String, dynamic> row) {
    final category = row['menu_categories'];
    int? categoryId;
    String? categorySlug;
    String? categoryNameAr;
    if (category is Map) {
      categoryId = (category['id'] as num?)?.toInt();
      categorySlug = category['slug'] as String?;
      categoryNameAr = (category['name_ar'] as String?) ?? categorySlug;
    }
    return AdminMenuItem(
      id: row['id'] as String,
      slug: (row['slug'] as String?) ?? '',
      nameAr: (row['name_ar'] as String?) ?? '',
      nameEn: (row['name_en'] as String?) ?? '',
      descAr: (row['desc_ar'] as String?) ?? '',
      descEn: (row['desc_en'] as String?) ?? '',
      priceEgp: (row['price_egp'] as num?)?.toInt() ?? 0,
      isAvailable: (row['is_available'] as bool?) ?? true,
      sort: (row['sort'] as num?)?.toInt() ?? 0,
      categoryId: categoryId,
      categorySlug: categorySlug,
      categoryNameAr: categoryNameAr,
    );
  }

  /// Full-row payload — also reused verbatim for delete-undo re-insertion.
  Map<String, dynamic> toPayload() => {
        'id': id,
        'slug': slug,
        'name_ar': nameAr,
        'name_en': nameEn,
        'desc_ar': descAr,
        'desc_en': descEn,
        'price_egp': priceEgp,
        'is_available': isAvailable,
        'sort': sort,
        'category_id': ?categoryId,
      };
}

/// Form values collected by the menu editor sheet.
class MenuItemDraft {
  const MenuItemDraft({
    required this.slug,
    required this.nameAr,
    required this.nameEn,
    required this.descAr,
    required this.descEn,
    required this.priceEgp,
    required this.categoryId,
    required this.sort,
  });

  final String slug;
  final String nameAr;
  final String nameEn;
  final String descAr;
  final String descEn;
  final int priceEgp;
  final int categoryId;
  final int sort;
}

class AdminMenuRepository {
  const AdminMenuRepository(this._db);

  final AdminDbClient _db;

  Future<({List<AdminCategory> categories, List<AdminMenuItem> items})>
      listCatalog() async {
    final rows = await _readOrEmpty(
      () => _db.select(
        'menu_items',
        columns: '*, menu_categories(id, slug, name_ar, name_en)',
        orderBy: 'sort',
      ),
    );
    final categories = <int, AdminCategory>{};
    final items = <AdminMenuItem>[];
    for (final row in rows) {
      final item = AdminMenuItem.fromRow(row);
      final catId = item.categoryId;
      final rawCat = row['menu_categories'];
      if (catId != null &&
          !categories.containsKey(catId) &&
          rawCat is Map &&
          rawCat['slug'] is String) {
        categories[catId] = AdminCategory(
          id: catId,
          slug: rawCat['slug'] as String,
          nameAr: (rawCat['name_ar'] as String?) ?? rawCat['slug'] as String,
          nameEn: (rawCat['name_en'] as String?) ?? rawCat['slug'] as String,
        );
      }
      items.add(item);
    }
    final sortedCategories = categories.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return (categories: sortedCategories, items: items);
  }

  /// Insert (new item) or update ([id] present). Slug must be unique —
  /// callers generate one via [generateSlug] for inserts.
  Future<void> upsertItem(MenuItemDraft draft, {String? id}) async {
    await _db.upsert('menu_items', {
      'id': ?id,
      'slug': draft.slug,
      'category_id': draft.categoryId,
      'name_ar': draft.nameAr,
      'name_en': draft.nameEn,
      'desc_ar': draft.descAr,
      'desc_en': draft.descEn,
      'price_egp': draft.priceEgp,
      'sort': draft.sort,
    });
  }

  Future<void> setAvailability(String id, bool available) async {
    await _db.update(
      'menu_items',
      {'is_available': available},
      whereColumn: 'id',
      whereValue: id,
    );
  }

  Future<void> deleteItem(String id) async {
    await _db.delete('menu_items', whereColumn: 'id', whereValue: id);
  }

  /// Undo path for deletes: re-inserts the exact previous row (same uuid).
  Future<void> reinsertRow(Map<String, dynamic> fullRow) async {
    await _db.insert('menu_items', fullRow);
  }

  /// Unique-enough slug for new items: EN-name slugified + timestamp tail
  /// (the column is NOT NULL UNIQUE).
  static String generateSlug(String nameEn) {
    final base = nameEn
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final salt = _slugSeq = (_slugSeq + 1) & 0xFFF;
    return '${base.isEmpty ? 'item' : base}-$stamp$salt';
  }

  static int _slugSeq = 0;
}

// ---------------------------------------------------------------------------
// Loyalty rules (app_config)
// ---------------------------------------------------------------------------

class RulesRepository {
  const RulesRepository(this._db);

  final AdminDbClient _db;

  /// Flat `{key: scalar}` of all editable config rows.
  Future<Map<String, dynamic>> fetchAll() async {
    final rows = await _readOrEmpty(() => _db.select('app_config'));
    return {
      for (final row in rows)
        row['key'] as String: row['value'],
    };
  }

  /// Upserts one jsonb scalar under [key].
  Future<void> save(String key, Object value) async {
    await _db.upsert(
      'app_config',
      {'key': key, 'value': value},
      onConflict: 'key',
    );
  }

  /// Keys surfaced in the rules editor, grouped for display.
  static const groups = <String, List<String>>{
    'points': ['points_per_10egp', 'dine_in_multiplier'],
    'stamps': [
      'stamp_min_spend',
      'redeem_min_points',
      'reward_topping',
      'reward_snack',
      'reward_drink',
    ],
    'delivery': ['delivery_fee'],
    'tiers': ['tier_silver', 'tier_gold'],
    'limits': ['rate_limit_max', 'rate_limit_window_min'],
  };

  /// Numeric keys whose edited value stays an integer (others keep doubles).
  static const intKeys = {
    'points_per_10egp',
    'stamp_min_spend',
    'redeem_min_points',
    'reward_topping',
    'reward_snack',
    'reward_drink',
    'delivery_fee',
    'tier_silver',
    'tier_gold',
    'rate_limit_max',
    'rate_limit_window_min',
  };
}

// ---------------------------------------------------------------------------
// KPI aggregates (computed client-side from an admin-wide orders select)
// ---------------------------------------------------------------------------

class AdminKpis {
  const AdminKpis({
    required this.ordersToday,
    required this.activeCustomers,
    required this.avgBasketEgp,
  });

  final int ordersToday;
  final int activeCustomers;
  final double avgBasketEgp;
}

/// Pure math over raw order rows — unit-tested without any db.
AdminKpis computeKpis(List<Map<String, dynamic>> rows, DateTime now) {
  final dayStart = DateTime(now.year, now.month, now.day);
  var ordersToday = 0;
  final phones = <String>{};
  var basketSum = 0;
  var basketCount = 0;
  for (final row in rows) {
    final created = parseAdminTimestamp(row['created_at']);
    if (created != null && !created.isBefore(dayStart)) ordersToday++;
    final phone = row['phone'];
    if (phone is String && phone.isNotEmpty) phones.add(phone);
    final amount = row['total'] ?? row['subtotal'];
    if (amount is num) {
      basketSum += amount.toInt();
      basketCount++;
    }
  }
  return AdminKpis(
    ordersToday: ordersToday,
    activeCustomers: phones.length,
    avgBasketEgp: basketCount == 0 ? 0 : basketSum / basketCount,
  );
}

class AdminKpiRepository {
  const AdminKpiRepository(this._db);

  final AdminDbClient _db;

  /// All-time orders probe (RLS lets admins read every Customer's rows):
  /// orders-today count, distinct-phone reach and mean basket.
  Future<AdminKpis> fetchKpis(DateTime now) async {
    final rows = await _readOrEmpty(
      () => _db.select(
        'orders',
        columns: 'phone, subtotal, total, created_at',
      ),
    );
    return computeKpis(rows, now);
  }

  /// Last-30-days rows feeding the reports tab (mode share + top item).
  Future<List<Map<String, dynamic>>> fetchRecentOrders(DateTime now) async {
    final cutoff =
        now.subtract(const Duration(days: 30)).toUtc().toIso8601String();
    return _readOrEmpty(
      () => _db.select(
        'orders',
        columns: 'mode, items, subtotal, total, created_at',
        gte: (column: 'created_at', value: cutoff),
      ),
    );
  }
}

/// Mode → order-count tallies over the reporting window.
Map<String, int> computeModeCounts(List<Map<String, dynamic>> rows) {
  final counts = {'dine_in': 0, 'pickup': 0, 'delivery': 0};
  for (final row in rows) {
    final mode = row['mode'];
    if (mode is String && counts.containsKey(mode)) counts[mode] = counts[mode]! + 1;
  }
  return counts;
}

/// Highest-selling item by qty across `orders.items` jsonb snapshots.
({String nameAr, int qty})? computeTopItem(List<Map<String, dynamic>> rows) {
  final qtyByName = <String, int>{};
  for (final row in rows) {
    final items = row['items'];
    if (items is! List) continue;
    for (final entry in items) {
      if (entry is! Map) continue;
      final name = entry['name_ar'];
      final qty = entry['qty'];
      if (name is! String || name.isEmpty) continue;
      qtyByName[name] = (qtyByName[name] ?? 0) + ((qty as num?)?.toInt() ?? 0);
    }
  }
  if (qtyByName.isEmpty) return null;
  String bestName = '';
  var bestQty = -1;
  qtyByName.forEach((name, qty) {
    if (qty > bestQty) {
      bestName = name;
      bestQty = qty;
    }
  });
  return (nameAr: bestName, qty: bestQty);
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final adminDbProvider = Provider<AdminDbClient>(
  (ref) => SupabaseAdminDb(supabase),
);

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (ref) => CampaignRepository(ref.watch(adminDbProvider)),
);

final adminMenuRepositoryProvider = Provider<AdminMenuRepository>(
  (ref) => AdminMenuRepository(ref.watch(adminDbProvider)),
);

final rulesRepositoryProvider = Provider<RulesRepository>(
  (ref) => RulesRepository(ref.watch(adminDbProvider)),
);

final adminKpiRepositoryProvider = Provider<AdminKpiRepository>(
  (ref) => AdminKpiRepository(ref.watch(adminDbProvider)),
);
