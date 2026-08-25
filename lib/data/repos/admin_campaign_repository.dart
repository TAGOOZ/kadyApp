// Campaign repository (#015, ARCH-02 split): campaigns / double-window flag.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_db.dart';

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
    final rows = await readOrEmpty(
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

  Future<void> delete(String id) async {
    await _db.delete('campaigns', whereColumn: 'id', whereValue: id);
  }
}

final campaignRepositoryProvider = Provider<CampaignRepository>(
  (ref) => CampaignRepository(ref.watch(adminDbProvider)),
);
