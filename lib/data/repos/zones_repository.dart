import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_db.dart';

class ZonesRepository {
  const ZonesRepository(this._db);
  final AdminDbClient _db;

  Future<List<Map<String, dynamic>>> fetchAll() =>
      _db.select('zones', orderBy: 'fee');

  Future<void> delete(String id) =>
      _db.delete('zones', whereColumn: 'id', whereValue: id);

  Future<void> update(String id, Map<String, dynamic> values) =>
      _db.update('zones', values, whereColumn: 'id', whereValue: id);

  Future<void> insert(Map<String, dynamic> values) =>
      _db.insert('zones', values);
}

final zonesRepositoryProvider = Provider<ZonesRepository>(
  (ref) => ZonesRepository(ref.watch(adminDbProvider)),
);
