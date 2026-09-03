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
        .select('phone, loyalty_state(points, lifetime_points, stamps, completed_cards, spinner_tokens, match_tokens, scratch_tokens, double_next_order, double_next_expires_at, vouchers, processed_orders)')
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

  @override
  Future<Map<String, dynamic>?> playSpinner({String? idempotencyKey}) async {
    try {
      final res = await _client.rpc('play_spinner',
          params: idempotencyKey == null ? null : {'p_idem': idempotencyKey});
      if (res == null) return null;
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> playMatch({String? idempotencyKey}) async {
    try {
      final res = await _client.rpc('play_match',
          params: idempotencyKey == null ? null : {'p_idem': idempotencyKey});
      if (res == null) return null;
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> playScratch({String? idempotencyKey}) async {
    try {
      final res = await _client.rpc('play_scratch',
          params: idempotencyKey == null ? null : {'p_idem': idempotencyKey});
      if (res == null) return null;
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> consumeSpinnerToken() async {
    try {
      final res = await _client.rpc('consume_spinner_token');
      if (res is bool) return res;
      return res != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> consumeMatchToken() async {
    try {
      final res = await _client.rpc('consume_match_token');
      if (res is bool) return res;
      return res != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> consumeScratchToken() async {
    try {
      final res = await _client.rpc('consume_scratch_token');
      if (res is bool) return res;
      return res != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> consumeVoucher(String voucherType) async {
    try {
      final res = await _client.rpc('consume_voucher', params: {'p_type': voucherType});
      if (res is bool) return res;
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> requestFreeToken({String? deviceId}) async {
    try {
      final params = deviceId == null || deviceId.isEmpty ? null : {'p_device_id': deviceId};
      final res = await _client.rpc('request_free_token', params: params);
      if (res == null) return null;
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } on PostgrestException catch (e) {
      final combined = '${e.hint} ${e.message} ${e.code}';
      if (combined.contains('free_token_rate_limited') || combined.contains('device_rate_limited') || combined.contains('device_flagged')) {
        throw const FreeTokenRateLimitedException();
      }
      if (combined.contains('token_cap')) {
        throw const TokenCapException();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> grantQuestTokens({int spinner = 0, int match = 0, int scratch = 0}) async {
    try {
      final res = await _client.rpc('grant_quest_tokens', params: {
        'p_spinner': spinner,
        'p_match': match,
        'p_scratch': scratch,
      });
      if (res == null) return null;
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> grantQuestPoints(int points) async {
    try {
      final res = await _client.rpc('grant_quest_points', params: {'p_points': points});
      if (res == null) return null;
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Default prod provider — wired in main.dart ProviderScope overrides.
/// Kept here for convenience; domain provider is the sourced token.
