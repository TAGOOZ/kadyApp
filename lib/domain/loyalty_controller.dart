import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_config.dart';
import 'loyalty_rules.dart';

/// Voucher types granted by stamp cards and games.
enum VoucherType { freeDrink, freeTopping, freeSnack }

extension VoucherTypeX on VoucherType {
  String get key => switch (this) {
        VoucherType.freeDrink => 'free_drink',
        VoucherType.freeTopping => 'free_topping',
        VoucherType.freeSnack => 'free_snack',
      };

  static VoucherType fromKey(String key) => switch (key) {
        'free_drink' => VoucherType.freeDrink,
        'free_topping' => VoucherType.freeTopping,
        'free_snack' => VoucherType.freeSnack,
        _ => VoucherType.freeSnack,
      };
}

class Voucher {
  const Voucher({required this.type, required this.grantedAt});
  final VoucherType type;
  final DateTime grantedAt;

  Map<String, dynamic> toJson() => {'type': type.key, 'at': grantedAt.toIso8601String()};
  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
        type: VoucherTypeX.fromKey(j['type'] as String),
        grantedAt: DateTime.parse(j['at'] as String),
      );
}

enum Tier { bronze, silver, gold }

/// Tier thresholds — mirrored from `app_config` seeds (admin-editable later, #015).
const int kTierSilver = 2000;
const int kTierGold = 5000;

Tier derivedTier(int lifetimePoints) {
  if (lifetimePoints >= kTierGold) return Tier.gold;
  if (lifetimePoints >= kTierSilver) return Tier.silver;
  return Tier.bronze;
}

class LoyaltyState {
  const LoyaltyState({
    this.points = 0,
    this.lifetimePoints = 0,
    this.stamps = 0,
    this.completedCards = 0,
    this.spinnerTokens = 0,
    this.matchTokens = 0,
    this.scratchTokens = 0,
    this.doubleNextOrder = false,
    this.vouchers = const [],
    this.processedOrders = const [],
  });

  final int points;
  final int lifetimePoints;
  final int stamps;
  final int completedCards;
  final int spinnerTokens;
  final int matchTokens;
  final int scratchTokens;
  final bool doubleNextOrder;
  final List<Voucher> vouchers;

  /// Order ids already credited — mirrors the `loyalty_state.processed_orders`
  /// jsonb guard list (idempotent crediting, #007).
  final List<String> processedOrders;

  Tier get tier => derivedTier(lifetimePoints);

  factory LoyaltyState.fromJson(Map<String, dynamic> j) => LoyaltyState(
        points: (j['points'] as num?)?.toInt() ?? 0,
        lifetimePoints: (j['lifetime_points'] as num?)?.toInt() ?? 0,
        stamps: (j['stamps'] as num?)?.toInt() ?? 0,
        completedCards: (j['completed_cards'] as num?)?.toInt() ?? 0,
        spinnerTokens: (j['spinner_tokens'] as num?)?.toInt() ?? 0,
        matchTokens: (j['match_tokens'] as num?)?.toInt() ?? 0,
        scratchTokens: (j['scratch_tokens'] as num?)?.toInt() ?? 0,
        doubleNextOrder: (j['double_next_order'] as bool?) ?? false,
        vouchers: ((j['vouchers'] as List?) ?? [])
            .map((v) => Voucher.fromJson(v as Map<String, dynamic>))
            .toList(),
        processedOrders: ((j['processed_orders'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
      );

  LoyaltyState copyWith({
    int? points,
    int? lifetimePoints,
    int? stamps,
    int? completedCards,
    int? spinnerTokens,
    int? matchTokens,
    int? scratchTokens,
    bool? doubleNextOrder,
    List<Voucher>? vouchers,
    List<String>? processedOrders,
  }) =>
      LoyaltyState(
        points: points ?? this.points,
        lifetimePoints: lifetimePoints ?? this.lifetimePoints,
        stamps: stamps ?? this.stamps,
        completedCards: completedCards ?? this.completedCards,
        spinnerTokens: spinnerTokens ?? this.spinnerTokens,
        matchTokens: matchTokens ?? this.matchTokens,
        scratchTokens: scratchTokens ?? this.scratchTokens,
        doubleNextOrder: doubleNextOrder ?? this.doubleNextOrder,
        vouchers: vouchers ?? this.vouchers,
        processedOrders: processedOrders ?? this.processedOrders,
      );
}

/// Reads/writes the signed-in Customer's `loyalty_state` row.
/// Auth-less (guest) sessions resolve to an empty zero state.
class LoyaltyController extends Notifier<LoyaltyState> {
  @override
  LoyaltyState build() => const LoyaltyState();

  SupabaseClient get _client => supabase;

  /// Loads state for the given authenticated google_user_id.
  Future<void> refreshFor(String googleUserId) async {
    try {
      final rows = await _client
          .from('customers')
          .select('phone, loyalty_state(points, lifetime_points, stamps, completed_cards, spinner_tokens, match_tokens, scratch_tokens, double_next_order, vouchers, processed_orders)')
          .eq('google_user_id', googleUserId)
          .limit(1);
      if (rows.isNotEmpty) {
        final inner = (rows.first as Map)['loyalty_state'];
        state = inner == null
            ? const LoyaltyState()
            : LoyaltyState.fromJson(Map<String, dynamic>.from(inner as Map));
      } else {
        state = const LoyaltyState();
      }
    } catch (_) {
      state = const LoyaltyState();
    }
  }

  void reset() => state = const LoyaltyState();

  // -- Admin-editable rules config (app_config) ------------------------------

  Map<String, dynamic>? _configCache;

  /// Flat `{key: scalar}` map of the `app_config` loyalty parameters
  /// (points_per_10egp, dine_in_multiplier, stamp_min_spend, redeem_min_points,
  /// reward_topping/snack/drink). Successful reads are cached for the session;
  /// failures return an empty map so [LoyaltyRulesConfig.fromMap] falls back to
  /// the seed constants (standard offline policy).
  Future<Map<String, dynamic>> loadConfig() async {
    final cached = _configCache;
    if (cached != null) return cached;
    try {
      final rows =
          await _client.from('app_config').select('key,value') as List;
      final map = <String, dynamic>{
        for (final row in rows.cast<Map>())
          row['key'] as String: row['value'],
      };
      _configCache = map;
      return map;
    } catch (_) {
      return const {};
    }
  }

  /// Drops the cache and re-reads `app_config` (used after admin edits).
  Future<void> refreshConfig() async {
    _configCache = null;
    await loadConfig();
  }

  // -- Real crediting (#007) -------------------------------------------------

  /// Credits one placed order exactly once. Idempotent via the
  /// `processed_orders` guard list: the current server row is read first and a
  /// repeat call for the same [orderId] is a no-op (local-only guest sessions
  /// get the same guarantee through the in-memory list). Earn/stamp/token math
  /// lives in the pure [creditOrder]/[earnedFor] rules; state updates
  /// optimistically before the full-row persist (RLS own-row UPDATE — accepted
  /// MVP cheat vector per ADR-0007 note in FEATURES §4).
  Future<void> creditProcessedOrder({
    required String orderId,
    required int subtotalEgp,
    required bool dineIn,
    Redemption? redemption,
  }) async {
    try {
      var base = state;
      String? phone;
      final uid = _client.auth.currentUser?.id;
      if (uid != null) {
        final rows = await _client
            .from('customers')
            .select('phone, loyalty_state(points, lifetime_points, stamps, completed_cards, spinner_tokens, match_tokens, scratch_tokens, double_next_order, vouchers, processed_orders)')
            .eq('google_user_id', uid)
            .limit(1);
        if (rows.isNotEmpty) {
          final row = (rows.first as Map);
          phone = row['phone'] as String?;
          final inner = row['loyalty_state'];
          if (inner != null) {
            base = LoyaltyState.fromJson(
                Map<String, dynamic>.from(inner as Map));
          }
        }
      }

      if (alreadyProcessed(base, orderId)) {
        if (phone != null) state = base; // resync with the credited row
        return;
      }

      final config = LoyaltyRulesConfig.fromMap(await loadConfig());
      final doubleWindow = base.doubleNextOrder ||
          (await loadConfig())['double_window_active'] == true;
      final earned = earnedFor(
        subtotalEgp: subtotalEgp,
        dineIn: dineIn,
        pointsPer10: config.pointsPer10Egp,
        dineInMultiplier: config.dineInMultiplier,
        doubleWindow: doubleWindow,
      );
      var next = creditRedeemedOrder(
        base,
        redemption: redemption,
        earned: earned,
        subtotalEgp: subtotalEgp,
        stampMinSpendEgp: config.stampMinSpendEgp,
      );
      next = markProcessed(next, orderId);
      if (doubleWindow) next = next.copyWith(doubleNextOrder: false);

      // Optimistic update first; persistence is best-effort.
      state = next;
      if (phone == null) return; // guest / customer row missing → local only
      await _client.from('loyalty_state').update({
        'points': next.points,
        'lifetime_points': next.lifetimePoints,
        'stamps': next.stamps,
        'completed_cards': next.completedCards,
        'spinner_tokens': next.spinnerTokens,
        'match_tokens': next.matchTokens,
        'scratch_tokens': next.scratchTokens,
        'double_next_order': next.doubleNextOrder,
        'vouchers': next.vouchers.map((v) => v.toJson()).toList(),
        'processed_orders': next.processedOrders,
      }).eq('phone', phone);
    } catch (_) {
      // Offline policy: optimistic local state stands.
    }
  }
  // -- Game tokens & grants (shared seam for slices #008/#009/#010) ----------

  /// Best-effort persist of the current [state] to the signed-in Customer's
  /// `loyalty_state` row (RLS own-row UPDATE). No-op when unauthenticated.
  Future<void> _persist() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await _client
          .from('customers')
          .select('phone')
          .eq('google_user_id', uid)
          .limit(1);
      if (rows.isEmpty) return;
      final phone = (rows.first as Map)['phone'] as String;
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
    } catch (_) {
      // Offline policy: optimistic local state stands.
    }
  }

  /// Consumes one game token; returns false when none available.
  Future<bool> consumeSpinnerToken() async {
    if (state.spinnerTokens <= 0) return false;
    state = state.copyWith(spinnerTokens: state.spinnerTokens - 1);
    await _persist();
    return true;
  }

  Future<bool> consumeMatchToken() async {
    if (state.matchTokens <= 0) return false;
    state = state.copyWith(matchTokens: state.matchTokens - 1);
    await _persist();
    return true;
  }

  Future<bool> consumeScratchToken() async {
    if (state.scratchTokens <= 0) return false;
    state = state.copyWith(scratchTokens: state.scratchTokens - 1);
    await _persist();
    return true;
  }

  /// Adds earned points to both balances and persists.
  Future<void> grantPoints(int n) async {
    if (n <= 0) return;
    state = state.copyWith(
      points: state.points + n,
      lifetimePoints: state.lifetimePoints + n,
    );
    await _persist();
  }

  Future<void> grantVoucher(VoucherType type) async {
    state = state.copyWith(
      vouchers: [...state.vouchers, Voucher(type: type, grantedAt: DateTime.now().toUtc())],
    );
    await _persist();
  }

  /// Arms the double-points-next-order prize (consumed on next credit).
  Future<void> setDoubleNextOrder() async {
    state = state.copyWith(doubleNextOrder: true);
    await _persist();
  }

  /// Grants game tokens directly (quest rewards). Mirrors #007 stamp-wrap
  /// semantics where a 3rd-stamp token also applies.
  Future<void> grantTokens({int spinner = 0, int match = 0, int scratch = 0}) async {
    if (spinner <= 0 && match <= 0 && scratch <= 0) return;
    state = state.copyWith(
      spinnerTokens: state.spinnerTokens + spinner,
      matchTokens: state.matchTokens + match,
      scratchTokens: state.scratchTokens + scratch,
    );
    await _persist();
  }

  /// Adds [n] stamps (no points): reaching 10 completes the card (snack
  /// voucher) and resets; every 3rd stamp also grants a spinner token.
  Future<void> grantStamps(int n) async {
    if (n <= 0) return;
    var s = state;
    for (var i = 0; i < n; i++) {
      final newStamps = s.stamps + 1;
      var stamps = newStamps;
      var cards = s.completedCards;
      var vouchers = List<Voucher>.of(s.vouchers);
      if (newStamps >= 10) {
        cards += 1;
        vouchers = [
          ...vouchers,
          Voucher(type: VoucherType.freeSnack, grantedAt: DateTime.now().toUtc()),
        ];
        stamps = newStamps - 10;
      }
      if (stamps % 3 == 0 && stamps > 0) {
        s = s.copyWith(spinnerTokens: s.spinnerTokens + 1);
      }
      s = s.copyWith(stamps: stamps, completedCards: cards, vouchers: vouchers);
    }
    state = s;
    await _persist();
  }
}

/// Admin-tuned loyalty rules for checkout/games; seed constants while loading
/// or offline.
final loyaltyConfigProvider = FutureProvider<LoyaltyRulesConfig>((ref) async {
  final raw = await ref.watch(loyaltyProvider.notifier).loadConfig();
  return LoyaltyRulesConfig.fromMap(raw);
});

final loyaltyProvider = NotifierProvider<LoyaltyController, LoyaltyState>(LoyaltyController.new);
