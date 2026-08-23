// Shared in-memory fake of the admin [AdminDbClient] seam — records every
// mutation and scripts SELECT results per table. Used by the widget tests;
// the unit tests keep an equivalent local fake.
import 'package:kady_app/data/repos/admin_repositories.dart';

class RecordedOp {
  const RecordedOp(
    this.op,
    this.table,
    this.values, {
    this.whereColumn,
    this.whereValue,
    this.onConflict,
  });

  final String op;
  final String table;
  final Map<String, dynamic> values;
  final String? whereColumn;
  final Object? whereValue;
  final String? onConflict;
}

class FakeAdminDb implements AdminDbClient {
  FakeAdminDb();

  /// Scripted SELECT results keyed by table name.
  final Map<String, List<Map<String, dynamic>>> tables = {};
  final List<RecordedOp> ops = [];
  bool denyReads = false;

  /// Bulk seed helper for readable test fixtures.
  Future<void> loadJson(Map<String, List<Map<String, dynamic>>> data) async {
    tables.addAll(data);
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
    if (denyReads) throw const AdminAccessDeniedException();
    ops.add(RecordedOp('select', table, {'columns': columns}));
    return [for (final row in tables[table] ?? const []) Map.of(row)];
  }

  @override
  Future<int> count(
    String table, {
    List<({String column, Object value})> eq = const [],
    ({String column, Object value})? gte,
  }) async {
    if (denyReads) throw const AdminAccessDeniedException();
    ops.add(RecordedOp('count', table, {
      if (gte != null) 'gte': '${gte.column}@${gte.value}',
    }));
    DateTime? asDate(Object? v) =>
        v is DateTime ? v : v is String ? DateTime.tryParse(v) : null;
    final rows = tables[table] ?? const [];
    if (gte == null) return rows.length;
    return rows.where((row) {
      final value = asDate(row[gte.column]);
      final bound = asDate(gte.value);
      return value != null && bound != null && !value.isBefore(bound);
    }).length;
  }

  @override
  Future<void> insert(String table, Map<String, dynamic> values) async {
    ops.add(RecordedOp('insert', table, values));
  }

  @override
  Future<void> update(
    String table,
    Map<String, dynamic> values, {
    required String whereColumn,
    required Object whereValue,
  }) async {
    ops.add(RecordedOp(
      'update',
      table,
      values,
      whereColumn: whereColumn,
      whereValue: whereValue,
    ));
  }

  @override
  Future<void> upsert(
    String table,
    Map<String, dynamic> values, {
    String onConflict = 'id',
  }) async {
    ops.add(RecordedOp('upsert', table, values, onConflict: onConflict));
  }

  @override
  Future<void> delete(
    String table, {
    required String whereColumn,
    required Object whereValue,
  }) async {
    ops.add(RecordedOp(
      'delete',
      table,
      const {},
      whereColumn: whereColumn,
      whereValue: whereValue,
    ));
  }
}
