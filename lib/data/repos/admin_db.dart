// Admin DB seam (#015, ARCH-02 split): shared low-level PostgREST client
// and read-degradation helpers. Every admin repository depends on this seam
// so unit tests can fake the database without Supabase.
//
// HoursRepository / ZonesRepository also depend only on this file (not the
// full admin_repositories barrel).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';

// ---------------------------------------------------------------------------
// Access-denied typing
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

// ---------------------------------------------------------------------------
// Db seam
// ---------------------------------------------------------------------------

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

  /// Server-side row count (`HEAD` + `Prefer: count=exact`) honoring the
  /// eq/gte filters — zero rows transferred (audit #6).
  Future<int> count(
    String table, {
    List<({String column, Object value})> eq = const [],
    ({String column, Object value})? gte,
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
  Future<int> count(
    String table, {
    List<({String column, Object value})> eq = const [],
    ({String column, Object value})? gte,
  }) async {
    try {
      var filtered = _client.from(table).count(CountOption.exact);
      for (final f in eq) {
        filtered = filtered.eq(f.column, f.value);
      }
      if (gte != null) {
        return await filtered.gte(gte.column, gte.value);
      }
      return await filtered;
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

Future<List<Map<String, dynamic>>> readOrEmpty(
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

/// Same degradation policy for head-count probes: ordinary failures → 0,
/// access denial rethrown so the lock panel shows.
Future<int> readCountOrZero(Future<int> Function() op) async {
  try {
    return await op();
  } on AdminAccessDeniedException {
    rethrow;
  } catch (_) {
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final adminDbProvider = Provider<AdminDbClient>(
  (ref) => SupabaseAdminDb(supabase),
);
