// LoyaltyGateway seam — domain-owned pure interface (ARCH-04 DAG).
// Data provides Supabase adapter in lib/data/adapters/supabase_loyalty_gateway.dart.
// Zero Supabase import here so domain stays pure and testable without network.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'loyalty_state.dart';

abstract class LoyaltyGateway {
  /// Current auth uid, or null when guest. Mirrors `supabase.auth.currentUser?.id`.
  String? get currentUserId;

  /// Fetches the joined loyalty row for [googleUserId].
  /// Returns null when no customers row exists. The returned [LoyaltyState]
  /// is the server row (not the in-memory state) so credit can be idempotent
  /// against the authoritative base.
  Future<({String phone, LoyaltyState state})?> fetchState(String googleUserId);

  /// Fetches the owner's phone for the signed-in uid.
  Future<String?> fetchPhone(String googleUserId);

  /// Flat `{key: scalar}` map of app_config loyalty params.
  Future<Map<String, dynamic>> fetchConfig();

  /// Realtime watch for a Customer's loyalty_state (phone key).
  /// Single writer: Postgres triggers (credit_new_order / staff_apply_stamp) own all writes.
  /// Client is read-only projection — two adapters justify seam (Supabase Realtime vs Fake).
  Stream<LoyaltyState> watchState(String phone);

  /// Server-authoritative game plays — SECURITY DEFINER RPCs that CHECK tokens>0
  /// and roll prize server side (mirror 0004 pattern). Returns prize payload.
  /// Throws on no_tokens (P0001) or not owned (42501). Null when offline/unauth.
  /// [idempotencyKey] is client Uuid.v4 per tap — same key replay returns same
  /// prize without consuming new token (038). Null => non-idempotent legacy.
  Future<Map<String, dynamic>?> playSpinner({String? idempotencyKey});
  Future<Map<String, dynamic>?> playMatch({String? idempotencyKey});
  Future<Map<String, dynamic>?> playScratch({String? idempotencyKey});

  /// Low-level token consume (legacy) — now server-authoritative.
  /// Returns true if token was consumed, false if none available or not owned.
  Future<bool> consumeSpinnerToken();
  Future<bool> consumeMatchToken();
  Future<bool> consumeScratchToken();

  /// Atomically consumes one voucher of [type] (FOR UPDATE). Returns true if consumed.
  Future<bool> consumeVoucher(String voucherType);

  /// No-purchase free token (FIX #1) — 1 per 7 days, respects token cap.
  /// Returns payload with new token count or null if rate-limited/capped.
  /// Throws [FreeTokenRateLimitedException] or [TokenCapException] for specific hints.
  /// `deviceId` optional per-device farm gate (0050) — stable `risk.device_id` UUID.
  Future<Map<String, dynamic>?> requestFreeToken({String? deviceId});

  /// Server-authoritative quest rewards (0050 thorough) — creates token ledger + respects cap 5
  Future<Map<String, dynamic>?> grantQuestTokens({int spinner = 0, int match = 0, int scratch = 0});
  Future<Map<String, dynamic>?> grantQuestPoints(int points);
}

class FreeTokenRateLimitedException implements Exception {
  const FreeTokenRateLimitedException();
}

class TokenCapException implements Exception {
  const TokenCapException();
}

class _NoopLoyaltyGateway implements LoyaltyGateway {
  @override
  String? get currentUserId => null;
  @override
  Future<({String phone, LoyaltyState state})?> fetchState(String googleUserId) async => null;
  @override
  Future<String?> fetchPhone(String googleUserId) async => null;
  @override
  Future<Map<String, dynamic>> fetchConfig() async => const {};
  @override
  Stream<LoyaltyState> watchState(String phone) => Stream.value(const LoyaltyState());
  @override
  Future<Map<String, dynamic>?> playSpinner({String? idempotencyKey}) async => null;
  @override
  Future<Map<String, dynamic>?> playMatch({String? idempotencyKey}) async => null;
  @override
  Future<Map<String, dynamic>?> playScratch({String? idempotencyKey}) async => null;
  @override
  Future<bool> consumeSpinnerToken() async => false;
  @override
  Future<bool> consumeMatchToken() async => false;
  @override
  Future<bool> consumeScratchToken() async => false;
  @override
  Future<bool> consumeVoucher(String voucherType) async => false;
  @override
  Future<Map<String, dynamic>?> requestFreeToken({String? deviceId}) async => null;
  @override
  Future<Map<String, dynamic>?> grantQuestTokens({int spinner = 0, int match = 0, int scratch = 0}) async => null;
  @override
  Future<Map<String, dynamic>?> grantQuestPoints(int points) async => null;
}

final loyaltyGatewayProvider = Provider<LoyaltyGateway>(
  (ref) => _NoopLoyaltyGateway(),
);
