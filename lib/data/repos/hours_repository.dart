import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_db.dart';

class HoursRepository {
  const HoursRepository(this._db);
  final AdminDbClient _db;

  Future<List<Map<String, dynamic>>> fetchAll() =>
      _db.select('hours', orderBy: 'day');

  Future<void> updateDay(int day, Map<String, dynamic> patch) =>
      _db.update('hours', patch, whereColumn: 'day', whereValue: day);
}

final hoursRepositoryProvider = Provider<HoursRepository>(
  (ref) => HoursRepository(ref.watch(adminDbProvider)),
);
