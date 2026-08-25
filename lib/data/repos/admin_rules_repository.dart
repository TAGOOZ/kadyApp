// Loyalty rules repository (#015, ARCH-02 split): app_config key/value editing.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_db.dart';

class RulesRepository {
  const RulesRepository(this._db);

  final AdminDbClient _db;

  /// Flat `{key: scalar}` of all editable config rows.
  Future<Map<String, dynamic>> fetchAll() async {
    final rows = await readOrEmpty(() => _db.select('app_config'));
    return {
      for (final row in rows) row['key'] as String: row['value'],
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
    'extras': ['double_window_active', 'group_checkin_count', 'group_bonus_points'],
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
    'group_checkin_count',
    'group_bonus_points',
  };

  static const boolKeys = {'double_window_active'};
}

final rulesRepositoryProvider = Provider<RulesRepository>(
  (ref) => RulesRepository(ref.watch(adminDbProvider)),
);
