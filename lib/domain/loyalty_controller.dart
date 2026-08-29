import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'loyalty_gateway.dart';
import 'loyalty_rules.dart';
import 'loyalty_state.dart';

export 'loyalty_state.dart';

/// Reads the signed-in Customer's `loyalty_state` row.
/// Server-authoritative: Postgres triggers (`credit_new_order` / `staff_apply_stamp`)
/// own all Points/Stamps/Voucher crediting. Client only previews (pure `loyalty_rules.dart`)
/// and resyncs via `refreshFor()` / `watchState`. No client-side point/stamp persistence
/// (AGENTS #4). Game token grants remain local-only preview for MVP (no persist).
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
        state = const LoyaltyState();
      }
      _lastRefreshFailed = false;
    } catch (_) {
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

  // -- Preview helpers (pure, no persistence) --------------------------------

  /// Preview earned Points for a subtotal (pure, delegates to `earnedFor`).
  int previewEarned({required int subtotalEgp, required bool dineIn, bool doubleWindow = false}) {
    final cfg = LoyaltyRulesConfig.fromMap(_configCache ?? const {});
    // Use cached config if available, otherwise fallback
    return earnedFor(
      subtotalEgp: subtotalEgp,
      dineIn: dineIn,
      pointsPer10: cfg.pointsPer10Egp,
      dineInMultiplier: cfg.dineInMultiplier,
      doubleWindow: doubleWindow || state.doubleNextOrder,
    );
  }

  /// Preview redeemable reward for current state (pure).
  Redemption? previewRedeemable({required bool hasDrinkLine}) {
    final cfg = LoyaltyRulesConfig.fromMap(_configCache ?? const {});
    return redeemable(state, hasDrinkLine: hasDrinkLine, config: cfg);
  }

  // -- Game tokens & grants (local-only preview, no server persist) ----------
  // Server-authoritative for orders, but games remain local for MVP.
  // These update in-memory state only; server trigger remains source of truth
  // for order-derived Points/Stamps. No gateway.persist call.

  /// Consumes one game token; returns false when none available (local only).
  Future<bool> consumeSpinnerToken() async {
    if (state.spinnerTokens <= 0) return false;
    state = state.copyWith(spinnerTokens: state.spinnerTokens - 1);
    return true;
  }

  Future<bool> consumeMatchToken() async {
    if (state.matchTokens <= 0) return false;
    state = state.copyWith(matchTokens: state.matchTokens - 1);
    return true;
  }

  Future<bool> consumeScratchToken() async {
    if (state.scratchTokens <= 0) return false;
    state = state.copyWith(scratchTokens: state.scratchTokens - 1);
    return true;
  }

  /// Adds earned points to both balances (local preview, no persist).
  Future<void> grantPoints(int n) async {
    if (n <= 0) return;
    state = state.copyWith(
      points: state.points + n,
      lifetimePoints: state.lifetimePoints + n,
    );
  }

  Future<void> grantVoucher(VoucherType type) async {
    state = state.copyWith(
      vouchers: [...state.vouchers, Voucher(type: type, grantedAt: DateTime.now().toUtc())],
    );
  }

  /// Arms the double-points-next-order prize (local preview).
  Future<void> setDoubleNextOrder() async {
    state = state.copyWith(doubleNextOrder: true);
  }

  /// Grants game tokens directly (quest rewards, local preview).
  Future<void> grantTokens({int spinner = 0, int match = 0, int scratch = 0}) async {
    if (spinner <= 0 && match <= 0 && scratch <= 0) return;
    state = state.copyWith(
      spinnerTokens: state.spinnerTokens + spinner,
      matchTokens: state.matchTokens + match,
      scratchTokens: state.scratchTokens + scratch,
    );
  }

  /// Adds [n] stamps (no points): reaching 10 completes the card (snack
  /// voucher) and resets; every 3rd stamp also grants a spinner token.
  /// Pure — delegates to canonical `grantStampsPure` (plan 002) shared with order
  /// credit and staff check-ins. Local preview only.
  Future<void> grantStamps(int n) async {
    if (n <= 0) return;
    state = grantStampsPure(state, n);
  }
}

/// Admin-tuned loyalty rules for checkout/games; seed constants while loading
/// or offline.
final loyaltyConfigProvider = FutureProvider<LoyaltyRulesConfig>((ref) async {
  final raw = await ref.watch(loyaltyProvider.notifier).loadConfig();
  return LoyaltyRulesConfig.fromMap(raw);
});

final loyaltyProvider = NotifierProvider<LoyaltyController, LoyaltyState>(LoyaltyController.new);

/// Auto-sync loyalty with auth (fix #4: stale after re-login).
/// Watches AuthPhase.ready and triggers refreshFor so home/profile show correct
/// server points without manual tap. Not used in pure unit tests (which override
/// gateway and don't need SharedPreferences), so it doesn't break `flutter test`.
/// App watches this in `KadyApp` to keep it alive.
final loyaltyAuthSyncProvider = Provider<void>((ref) {
  ref.listen(authControllerProvider, (previous, next) {
    final nextId = next.googleUser?.id;
    final prevId = previous?.googleUser?.id;
    final nextPhase = next.phase;
    final prevPhase = previous?.phase;
    if (nextPhase == AuthPhase.ready && nextId != null && nextId.isNotEmpty) {
      if (prevPhase != AuthPhase.ready || prevId != nextId) {
        Future.microtask(
          () => ref.read(loyaltyProvider.notifier).refreshFor(nextId),
        );
      }
    } else if ((nextPhase == AuthPhase.idle || nextPhase == AuthPhase.guest) &&
        prevPhase == AuthPhase.ready) {
      Future.microtask(() => ref.read(loyaltyProvider.notifier).reset());
    }
  });
  final auth = ref.read(authControllerProvider);
  if (auth.phase == AuthPhase.ready &&
      auth.googleUser?.id != null &&
      auth.googleUser!.id.isNotEmpty) {
    Future.microtask(
      () => ref.read(loyaltyProvider.notifier).refreshFor(auth.googleUser!.id),
    );
  }
});
