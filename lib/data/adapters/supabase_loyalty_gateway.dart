// Supabase implementation of LoyaltyGateway — data-layer adapter.
// Domain owns the interface (lib/domain/loyalty_gateway.dart); this file owns Supabase.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/loyalty_gateway.dart';
import '../../domain/loyalty_state.dart';

class SupabaseLoyaltyGateway implements LoyaltyGateway {
  const SupabaseLoyaltyGateway(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<({String phone, LoyaltyState state})?> fetchState(String googleUserId) async {
    final rows = await _client
        .from('customers')
        .select('phone, loyalty_state(points, lifetime_points, stamps, completed_cards, spinner_tokens, match_tokens, scratch_tokens, double_next_order, vouchers, processed_orders)')
        .eq('google_user_id', googleUserId)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = rows.first as Map;
    final phone = row['phone'] as String?;
    if (phone == null) return null;
    final inner = row['loyalty_state'];
    final state = inner == null
        ? const LoyaltyState()
        : LoyaltyState.fromJson(Map<String, dynamic>.from(inner as Map));
    return (phone: phone, state: state);
  }

  @override
  Future<String?> fetchPhone(String googleUserId) async {
    final rows = await _client
        .from('customers')
        .select('phone')
        .eq('google_user_id', googleUserId)
        .limit(1);
    if (rows.isEmpty) return null;
    return (rows.first as Map)['phone'] as String?;
  }

  @override
  Future<Map<String, dynamic>> fetchConfig() async {
    try {
      final rows = await _client.from('app_config').select('key,value') as List;
      return {
        for (final row in rows.cast<Map>()) row['key'] as String: row['value'],
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Stream<LoyaltyState> watchState(String phone) {
    return _client
        .from('loyalty_state')
        .stream(primaryKey: ['phone'])
        .eq('phone', phone)
        .map((rows) {
          if (rows.isEmpty) return const LoyaltyState();
          // ignore: unnecessary_cast
          final row = rows.first as Map<String, dynamic>;
          return LoyaltyState.fromJson(Map<String, dynamic>.from(row));
        });
  }
}

/// Default prod provider — wired in main.dart ProviderScope overrides.
/// Kept here for convenience; domain provider is the sourced token.
