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
}

final loyaltyGatewayProvider = Provider<LoyaltyGateway>(
  (ref) => _NoopLoyaltyGateway(),
);
