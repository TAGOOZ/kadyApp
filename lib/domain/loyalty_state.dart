// Pure state for loyalty — extracted to break domain/loyalty_controller ↔
// domain/loyalty_gateway cycle (ARCH-05). Controller and gateway both depend
// on this; it depends on neither.

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
  const Voucher({
    required this.type,
    required this.grantedAt,
    this.id,
    this.expiresAt,
    this.source,
  });
  final VoucherType type;
  final DateTime grantedAt;
  final String? id;
  final DateTime? expiresAt;
  final String? source;

  bool get isExpired => expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt!);
  bool get isExpiringSoon {
    if (expiresAt == null) return false;
    final now = DateTime.now().toUtc();
    return expiresAt!.isAfter(now) && expiresAt!.difference(now).inDays <= 2;
  }

  Map<String, dynamic> toJson() => {
        'type': type.key,
        'at': grantedAt.toIso8601String(),
        if (id != null) 'id': id,
        if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
        if (source != null) 'source': source,
      };
  factory Voucher.fromJson(Map<String, dynamic> j) => Voucher(
        type: VoucherTypeX.fromKey(j['type'] as String),
        grantedAt: DateTime.parse(j['at'] as String),
        id: j['id'] as String?,
        expiresAt: j['expires_at'] == null ? null : DateTime.tryParse(j['expires_at'] as String),
        source: j['source'] as String?,
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
    this.doubleNextExpiresAt,
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
  final DateTime? doubleNextExpiresAt;
  final List<Voucher> vouchers;

  /// Order ids already credited — mirrors the `loyalty_state.processed_orders`
  /// jsonb guard list (idempotent crediting, #007).
  final List<String> processedOrders;

  Tier get tier => derivedTier(lifetimePoints);

  /// True when doubleNext is active and not expired (0046: 7d default).
  bool get isDoubleNextActive {
    if (!doubleNextOrder) return false;
    final exp = doubleNextExpiresAt;
    if (exp == null) return true;
    return DateTime.now().toUtc().isBefore(exp);
  }

  factory LoyaltyState.fromJson(Map<String, dynamic> j) => LoyaltyState(
        points: (j['points'] as num?)?.toInt() ?? 0,
        lifetimePoints: (j['lifetime_points'] as num?)?.toInt() ?? 0,
        stamps: (j['stamps'] as num?)?.toInt() ?? 0,
        completedCards: (j['completed_cards'] as num?)?.toInt() ?? 0,
        spinnerTokens: (j['spinner_tokens'] as num?)?.toInt() ?? 0,
        matchTokens: (j['match_tokens'] as num?)?.toInt() ?? 0,
        scratchTokens: (j['scratch_tokens'] as num?)?.toInt() ?? 0,
        doubleNextOrder: (j['double_next_order'] as bool?) ?? false,
        doubleNextExpiresAt: j['double_next_expires_at'] == null
            ? null
            : DateTime.tryParse(j['double_next_expires_at'] as String),
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
    DateTime? doubleNextExpiresAt,
    List<Voucher>? vouchers,
    List<String>? processedOrders,
    bool clearDoubleNextExpiry = false,
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
        doubleNextExpiresAt: clearDoubleNextExpiry ? null : (doubleNextExpiresAt ?? this.doubleNextExpiresAt),
        vouchers: vouchers ?? this.vouchers,
        processedOrders: processedOrders ?? this.processedOrders,
      );
}
