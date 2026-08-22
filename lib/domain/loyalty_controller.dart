import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase/supabase_config.dart';

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
          .select('phone, loyalty_state(points, lifetime_points, stamps, completed_cards, spinner_tokens, match_tokens, scratch_tokens, double_next_order, vouchers)')
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

  /// DEV-ONLY boost used by debug affordances until slice #007 wires real crediting.
  /// Applies the same math locally and best-effort persists to `loyalty_state`
  /// (customer may UPDATE own row per RLS).
  Future<void> applyDemoBoost() async {
    var s = state.copyWith(
      points: state.points + 9,
      lifetimePoints: state.lifetimePoints + 9,
    );
    var stamps = s.stamps + 1;
    var spinner = s.spinnerTokens;
    var cards = s.completedCards;
    var vouchers = List<Voucher>.of(s.vouchers);
    if (stamps > 10) {
      stamps = 1;
      cards += 1;
      vouchers.add(Voucher(type: VoucherType.freeSnack, grantedAt: DateTime.now().toUtc()));
    }
    if (stamps % 3 == 0) spinner += 1;
    s = s.copyWith(stamps: stamps, spinnerTokens: spinner, completedCards: cards, vouchers: vouchers);
    state = s;
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      final rows = await _client
          .from('customers')
          .select('phone')
          .eq('google_user_id', uid)
          .limit(1);
      if (rows.isNotEmpty) {
        final phone = (rows.first as Map)['phone'] as String;
        await _client.from('loyalty_state').update({
          'points': s.points,
          'lifetime_points': s.lifetimePoints,
          'stamps': s.stamps,
          'completed_cards': s.completedCards,
          'spinner_tokens': s.spinnerTokens,
          'vouchers': s.vouchers.map((v) => v.toJson()).toList(),
        }).eq('phone', phone);
      }
    } catch (_) {
      // Offline/dev: local state already updated; real crediting lands with slice #007.
    }
  }
}

final loyaltyProvider = NotifierProvider<LoyaltyController, LoyaltyState>(LoyaltyController.new);
