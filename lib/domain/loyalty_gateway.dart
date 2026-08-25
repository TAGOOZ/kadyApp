// LoyaltyGateway seam — abstracts Supabase away from LoyaltyController (ARCH-05).
// Domain owns the interface; data provides Supabase implementation so
// controller tests can use an in-memory fake without touching network.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_config.dart';
import 'loyalty_state.dart';

abstract class LoyaltyGateway {
  /// Current auth uid, or null when guest. Mirrors `supabase.auth.currentUser?.id`.
  String? get currentUserId;

  /// Fetches the joined loyalty row for [googleUserId].
  /// Returns null when no customers row exists. The returned [LoyaltyState]
  /// is the server row (not the in-memory state) so credit can be idempotent
  /// against the authoritative base.
  Future<({String phone, LoyaltyState state})?> fetchState(String googleUserId);

  /// Fetches the owner's phone for the signed-in uid (used by _persist).
  Future<String?> fetchPhone(String googleUserId);

  /// Flat `{key: scalar}` map of app_config loyalty params.
  Future<Map<String, dynamic>> fetchConfig();

  /// Persists [state] for [phone] via RPC (SECURITY-01). No-op on guest.
  Future<void> persist(String phone, LoyaltyState state);
}

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
  Future<void> persist(String phone, LoyaltyState state) async {
    try {
      await _client.rpc('persist_loyalty_state', params: {
        'p_phone': phone,
        'p_points': state.points,
        'p_lifetime_points': state.lifetimePoints,
        'p_stamps': state.stamps,
        'p_completed_cards': state.completedCards,
        'p_spinner_tokens': state.spinnerTokens,
        'p_match_tokens': state.matchTokens,
        'p_scratch_tokens': state.scratchTokens,
        'p_double_next_order': state.doubleNextOrder,
        'p_vouchers': state.vouchers.map((v) => v.toJson()).toList(),
        'p_processed_orders': state.processedOrders,
      });
      return;
    } catch (_) {
      try {
        await _client.from('loyalty_state').update({
          'points': state.points,
          'lifetime_points': state.lifetimePoints,
          'stamps': state.stamps,
          'completed_cards': state.completedCards,
          'spinner_tokens': state.spinnerTokens,
          'match_tokens': state.matchTokens,
          'scratch_tokens': state.scratchTokens,
          'double_next_order': state.doubleNextOrder,
          'vouchers': state.vouchers.map((v) => v.toJson()).toList(),
          'processed_orders': state.processedOrders,
        }).eq('phone', phone);
      } catch (_) {}
    }
  }
}

final loyaltyGatewayProvider = Provider<LoyaltyGateway>(
  (ref) => SupabaseLoyaltyGateway(supabase),
);
