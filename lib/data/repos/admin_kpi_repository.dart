// KPI repository (#015, ARCH-02 split): bounded aggregates over orders.
// Pure math helpers are unit-tested without any db.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_db.dart';

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

/// Pure math over bounded rows — unit-tested without any db.

/// Distinct Customer phones across [rows] (non-empty strings only).
int distinctPhones(List<Map<String, dynamic>> rows) {
  return {
    for (final row in rows)
      if (row['phone'] is String && (row['phone'] as String).isNotEmpty)
        row['phone'] as String,
  }.length;
}

/// Rolling mean of `total ?? subtotal` over [rows]; 0 when nothing is priced.
double averageBasketEgp(List<Map<String, dynamic>> rows) {
  var basketSum = 0;
  var basketCount = 0;
  for (final row in rows) {
    final amount = row['total'] ?? row['subtotal'];
    if (amount is num) {
      basketSum += amount.toInt();
      basketCount++;
    }
  }
  return basketCount == 0 ? 0 : basketSum / basketCount;
}

class AdminKpiRepository {
  const AdminKpiRepository(this._db);

  final AdminDbClient _db;

  /// Bounded KPI probes (audit #6): orders-today via a server-side HEAD
  /// `count=exact` request; active Customers = distinct phones over a
  /// phone-column-only select of the last 30 days (PostgREST cannot count
  /// DISTINCT head-only — documented trade-off, payload stays one column);
  /// mean basket over the same 30-day window. Mode counts in the reports
  /// tab were already windowed by [fetchRecentOrders].
  Future<AdminKpis> fetchKpis(DateTime now) async {
    final dayStartUtc =
        DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final monthCutoff =
        now.subtract(const Duration(days: 30)).toUtc().toIso8601String();

    final results = await Future.wait([
      readCountOrZero(
        () => _db.count(
          'orders',
          gte: (column: 'created_at', value: dayStartUtc),
        ),
      ),
      readOrEmpty(
        () => _db.select(
          'orders',
          columns: 'phone, subtotal, total',
          gte: (column: 'created_at', value: monthCutoff),
        ),
      ),
    ]);
    final ordersToday = results[0] as int;
    final rows30d = results[1] as List<Map<String, dynamic>>;
    return AdminKpis(
      ordersToday: ordersToday,
      activeCustomers: distinctPhones(rows30d),
      avgBasketEgp: averageBasketEgp(rows30d),
    );
  }

  /// Last-30-days rows feeding the reports tab (mode share + top item).
  Future<List<Map<String, dynamic>>> fetchRecentOrders(DateTime now) async {
    final cutoff =
        now.subtract(const Duration(days: 30)).toUtc().toIso8601String();
    return readOrEmpty(
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

final adminKpiRepositoryProvider = Provider<AdminKpiRepository>(
  (ref) => AdminKpiRepository(ref.watch(adminDbProvider)),
);
