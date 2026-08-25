import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'loyalty_gateway.dart';
import 'loyalty_rules.dart';
import 'loyalty_state.dart';

export 'loyalty_state.dart';

/// Reads/writes the signed-in Customer's `loyalty_state` row.
/// Auth-less (guest) sessions resolve to an empty zero state.
class LoyaltyController extends Notifier<LoyaltyState> {
  @override
  LoyaltyState build() => const LoyaltyState();

  LoyaltyGateway get _gateway => ref.read(loyaltyGatewayProvider);

  /// Loads state for the given authenticated google_user_id.
  ///
  /// Audit finding #9: a network/permission failure must NOT be conflated
  /// with "customer has no state" — keep the last-known state and surface
  /// [lastRefreshFailed] instead of wiping displayed balances to zeros
  /// (a later grant would otherwise persist from the wiped base).
  Future<void> refreshFor(String googleUserId) async {
    try {
      final fetched = await _gateway.fetchState(googleUserId);
      if (fetched != null) {
        state = fetched.state;
      } else {
        // No customers row → zero state (genuine empty, not failure)
        // Check if fetch returned null due to missing row vs error:
        // fetchState returns null only on missing row; errors throw and are caught below.
        state = const LoyaltyState();
      }
      _lastRefreshFailed = false;
    } catch (_) {
      // Keep last-known state; only a genuine empty row zeroes it above.
      _lastRefreshFailed = true;
    }
  }

  /// True when the most recent [refreshFor] failed (stale data on screen).
  bool get lastRefreshFailed => _lastRefreshFailed;
  bool _lastRefreshFailed = false;

  void reset() {
    state = const LoyaltyState();
    _lastRefreshFailed = false;
  }

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
      final map = await _gateway.fetchConfig();
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
      final uid = _gateway.currentUserId;
      if (uid != null) {
        try {
          final fetched = await _gateway.fetchState(uid);
          if (fetched != null) {
            phone = fetched.phone;
            base = fetched.state;
          } else {
            // No row yet — keep in-memory base, phone stays null → local only
            phone = await _gateway.fetchPhone(uid);
          }
        } catch (_) {
          // Fetch failed → keep in-memory base, treat as offline
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

      // Optimistic update first; persistence via gateway (SECURITY-01)
      state = next;
      if (phone == null) return; // guest / customer row missing → local only
      try {
        await _gateway.persist(phone, next);
      } catch (_) {}
    } catch (_) {
      // Offline policy: optimistic local state stands.
    }
  }
  // -- Game tokens & grants (shared seam for slices #008/#009/#010) ----------

  /// Best-effort persist of the current [state] to the signed-in Customer's
  /// `loyalty_state` row via gateway (SECURITY-01). No-op when unauthenticated.
  Future<void> _persist() async {
    try {
      final uid = _gateway.currentUserId;
      if (uid == null) return;
      final phone = await _gateway.fetchPhone(uid);
      if (phone == null) return;
      await _gateway.persist(phone, state);
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
  /// Delegates to the canonical pure rule (plan 002) shared with order
  /// credit and staff check-ins.
  Future<void> grantStamps(int n) async {
    if (n <= 0) return;
    state = grantStampsPure(state, n);
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
