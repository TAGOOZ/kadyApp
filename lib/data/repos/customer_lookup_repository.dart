// Customer lookup + manual rewards slice (#013, FEATURES §6.4): staff search
// over `customers` (phone/name ilike, limit 10), a per-phone profile read
// (customer + loyalty_state + last 5 orders + visits count), manual reward
// grants (loyalty_state UPDATE + best-effort `staff_log` audit row) and walk-in
// visit registration reusing the exact staff-board semantics (#012). The
// Supabase client sits behind the [CustomerLookupDb] seam so unit tests inject
// fakes and never touch the network; Postgres 42501 (RLS denial — e.g. the
// loyalty_state own-row UPDATE policy) surfaces as the typed
// [StaffPermissionException] until profiles.role is elevated
// (docs/SUPABASE_SETUP.md — Elevate). Recent searches persist locally under
// the `lookup.recent` SharedPreferences key (max 5).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../repos/orders_repository.dart'; // cairoUtcOffset (ADR-0009 display)
import 'staff_orders_repository.dart';

// ---------------------------------------------------------------------------
// Search-term normalization (pure)
// ---------------------------------------------------------------------------

/// Strips whitespace and `+20` variants so phone fragments match the canonical
/// `+20XXXXXXXXXX` column: `+20 100 123 4567` → `1001234567`,
/// `201001234567` → `1001234567`; plain digits and Arabic names pass through.
/// The name match keeps the raw trimmed term (names contain spaces).
String normalizeSearchTerm(String raw) {
  final compact = raw.trim().replaceAll(RegExp(r'\s+'), '');
  final withoutPlus = compact.replaceAll('+', '');
  // `20` + at least one local digit beyond the 11-digit local form → strip.
  if (withoutPlus.startsWith('20') && withoutPlus.length > 11) {
    return withoutPlus.substring(2);
  }
  return withoutPlus;
}

// ---------------------------------------------------------------------------
// Read models
// ---------------------------------------------------------------------------

/// One search hit (`customers` row projected to the business key + name).
class CustomerHit {
  const CustomerHit({required this.phone, required this.name});

  final String phone;
  final String name;

  static CustomerHit fromRow(Map<String, dynamic> row) => CustomerHit(
        phone: row['phone'] as String,
        name: (row['name'] as String?) ?? '',
      );
}

/// One flattened recent order line for the profile mini-list.
class LookupOrder {
  const LookupOrder({required this.createdAtUtc, this.totalEgp});

  final DateTime createdAtUtc;
  final int? totalEgp;

  static LookupOrder fromRow(Map<String, dynamic> row) => LookupOrder(
        createdAtUtc: DateTime.parse(row['created_at'] as String),
        totalEgp: row['total'] is num ? (row['total'] as num).toInt() : null,
      );
}

/// Aggregated per-phone snapshot rendered by the result card.
class CustomerProfile {
  const CustomerProfile({
    required this.phone,
    required this.name,
    required this.points,
    required this.lifetimePoints,
    required this.stamps,
    required this.visits,
    required this.recentOrders,
  });

  final String phone;
  final String name;
  final int points;
  final int lifetimePoints;
  final int stamps;
  final int visits;
  final List<LookupOrder> recentOrders;
}

/// One `staff_log` row for the activity sheet.
class StaffActivity {
  const StaffActivity({
    this.actor,
    required this.action,
    required this.atUtc,
    this.detail = const {},
  });

  final String? actor;
  final String action;
  final DateTime atUtc;
  final Map<String, dynamic> detail;

  static StaffActivity fromRow(Map<String, dynamic> row) => StaffActivity(
        actor: row['actor'] as String?,
        action: (row['action'] as String?) ?? '',
        atUtc: DateTime.parse(row['at'] as String),
        detail: row['detail'] is Map
            ? Map<String, dynamic>.from(row['detail'] as Map)
            : const {},
      );
}

// ---------------------------------------------------------------------------
// Manual reward inputs + pure payload builders
// ---------------------------------------------------------------------------

enum ManualRewardType { points25, freeDrink, freeTopping }

extension ManualRewardTypeX on ManualRewardType {
  /// Wire vocabulary stored in `staff_log.detail.reward` / vouchers jsonb.
  String get wire => switch (this) {
        ManualRewardType.points25 => 'points25',
        ManualRewardType.freeDrink => 'free_drink',
        ManualRewardType.freeTopping => 'free_topping',
      };
}

enum ManualReason { lateApology, newGuest, other }

extension ManualReasonX on ManualReason {
  /// Wire vocabulary stored in `staff_log.detail.reason`.
  String get wire => switch (this) {
        ManualReason.lateApology => 'late_apology',
        ManualReason.newGuest => 'new_guest',
        ManualReason.other => 'other',
      };
}

/// Sheet outcome handed to [CustomerLookupRepo.grantManualReward].
class ManualRewardInput {
  const ManualRewardInput({
    required this.type,
    required this.reason,
    this.note = '',
  });

  final ManualRewardType type;
  final ManualReason reason;
  final String note;
}

/// loyalty_state UPDATE patch for one grant. Points add to both balances
/// (manual grant is an earn event — lifetime drives Tier); vouchers append a
/// jsonb entry shaped exactly like LoyaltyController's `{type, at}` rows.
Map<String, dynamic> manualRewardLoyaltyPatch(
  Map<String, dynamic>? current,
  ManualRewardInput reward, {
  DateTime? grantedAtUtc,
}) {
  int intOf(Object? value) => value is num ? value.toInt() : 0;
  switch (reward.type) {
    case ManualRewardType.points25:
      return {
        'points': intOf(current?['points']) + 25,
        'lifetime_points': intOf(current?['lifetime_points']) + 25,
      };
    case ManualRewardType.freeDrink:
    case ManualRewardType.freeTopping:
      final existing = current?['vouchers'] is List
          ? List<Map<String, dynamic>>.from(
              (current!['vouchers'] as List).map(
                (v) => Map<String, dynamic>.from(v as Map),
              ),
            )
          : <Map<String, dynamic>>[];
      return {
        'vouchers': [
          ...existing,
          {
            'type': reward.type.wire,
            'at': (grantedAtUtc ?? DateTime.now().toUtc()).toIso8601String(),
          },
        ],
      };
  }
}

/// Best-effort audit row in `staff_log` (#0001_init.sql §13) — same shape as
/// the check-in row, action `manual_reward`.
Map<String, dynamic> manualRewardStaffLogRow(
  String phone,
  ManualRewardInput reward,
) {
  final note = reward.note.trim();
  return {
    'actor': 'staff',
    'action': 'manual_reward',
    'target_phone': phone,
    'detail': {
      'reward': reward.type.wire,
      'reason': reward.reason.wire,
      if (note.isNotEmpty) 'note': note,
    },
  };
}

/// Cairo wall clock `dd/MM HH:mm` Western digits (§11.11, ADR-0009) for the
/// activity sheet and orders mini-list.
String formatLookupWhenUtc(DateTime utcInstant) {
  final naiveCairo = utcInstant.add(cairoUtcOffset(utcInstant));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(naiveCairo.day)}/${two(naiveCairo.month)} '
      '${two(naiveCairo.hour)}:${two(naiveCairo.minute)}';
}

// ---------------------------------------------------------------------------
// Recent searches — SharedPreferences `lookup.recent` (max 5)
// ---------------------------------------------------------------------------

class RecentSearchStore {
  RecentSearchStore(this._prefs);

  static const key = 'lookup.recent';

  final SharedPreferences _prefs;

  List<String> list() => _prefs.getStringList(key) ?? const [];

  /// Moves [term] to the front, deduplicated, capped at 5 entries.
  Future<void> add(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    final deduped = [
      trimmed,
      ...list().where((entry) => entry != trimmed),
    ];
    await _prefs.setStringList(
      key,
      deduped.length > 5 ? deduped.sublist(0, 5) : deduped,
    );
  }

  Future<void> remove(String term) async {
    await _prefs.setStringList(
      key,
      list().where((entry) => entry != term).toList(),
    );
  }

  Future<void> clear() async => _prefs.remove(key);
}

// ---------------------------------------------------------------------------
// Database seam — abstract enough for fakes, thin adapter for Supabase
// ---------------------------------------------------------------------------

abstract class CustomerLookupDb {
  /// `customers where phone ilike [phoneLike] or name ilike [nameLike]`.
  Future<List<Map<String, dynamic>>> searchCustomers(
    String phoneLike,
    String nameLike,
  );

  Future<Map<String, dynamic>?> fetchCustomer(String phone);

  Future<Map<String, dynamic>?> fetchLoyalty(String phone);

  /// Last [limit] orders of one phone, newest first.
  Future<List<Map<String, dynamic>>> fetchRecentOrders(String phone, int limit);

  Future<int> fetchVisitsCount(String phone);

  Future<void> updateLoyalty(String phone, Map<String, dynamic> patch);

  Future<void> insertStaffLog(Map<String, dynamic> row);

  Future<List<Map<String, dynamic>>> fetchStaffLog(String phone, int limit);

  // Visit path — identical semantics to the staff board (#012).
  Future<void> insertVisit(Map<String, dynamic> row);

  Future<int?> fetchStampMinSpend();

  Future<int?> fetchStamps(String phone);

  Future<void> updateStamps(String phone, int stamps);
}

class SupabaseCustomerLookupDb implements CustomerLookupDb {
  SupabaseCustomerLookupDb(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> searchCustomers(
    String phoneLike,
    String nameLike,
  ) async {
    try {
      // Single OR filter per spec; terms never contain Postgrest's `,`
      // separator in practice (phone digits / Arabic names).
      final rows = await _client //
          .from('customers')
          .select('phone, name')
          .or('phone.ilike.$phoneLike,name.ilike.$nameLike')
          .limit(10);
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchCustomer(String phone) async {
    try {
      final row = await _client //
          .from('customers')
          .select('phone, name')
          .eq('phone', phone)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row as Map);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchLoyalty(String phone) async {
    try {
      final row = await _client //
          .from('loyalty_state')
          .select()
          .eq('phone', phone)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row as Map);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRecentOrders(
    String phone,
    int limit,
  ) async {
    try {
      final rows = await _client //
          .from('orders')
          .select('created_at, total')
          .eq('phone', phone)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<int> fetchVisitsCount(String phone) async {
    try {
      final rows =
          await _client.from('visits').select('id').eq('phone', phone);
      return (rows as List).length;
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<void> updateLoyalty(String phone, Map<String, dynamic> patch) async {
    try {
      await _client.from('loyalty_state').update(patch).eq('phone', phone);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<void> insertStaffLog(Map<String, dynamic> row) async {
    try {
      await _client.from('staff_log').insert(row);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStaffLog(
    String phone,
    int limit,
  ) async {
    try {
      final rows = await _client //
          .from('staff_log')
          .select()
          .eq('target_phone', phone)
          .order('at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<void> insertVisit(Map<String, dynamic> row) async {
    try {
      await _client.from('visits').insert(row);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }

  @override
  Future<int?> fetchStampMinSpend() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'stamp_min_spend')
          .maybeSingle();
      final value = row?['value'];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
    } on PostgrestException {
      return null; // config read hiccup → constant threshold
    }
    return null;
  }

  @override
  Future<int?> fetchStamps(String phone) async {
    try {
      final row = await _client
          .from('loyalty_state')
          .select('stamps')
          .eq('phone', phone)
          .maybeSingle();
      final stamps = row?['stamps'];
      return stamps is num ? stamps.toInt() : null;
    } on PostgrestException catch (error) {
      return rethrowAsTyped(error);
    }
  }

  @override
  Future<void> updateStamps(String phone, int stamps) async {
    try {
      await _client
          .from('loyalty_state')
          .update({'stamps': stamps}).eq('phone', phone);
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
  }
}

// ---------------------------------------------------------------------------
// Repository seam + implementation
// ---------------------------------------------------------------------------

abstract class CustomerLookupRepo {
  /// Customers matching a phone fragment or name substring, max 10.
  Future<List<CustomerHit>> search(String term);

  /// Full account snapshot for the result card.
  Future<CustomerProfile> loadProfile(String phone);

  /// Credits the grant through loyalty_state and appends the `staff_log`
  /// audit row (best-effort). Throws [StaffPermissionException] when RLS
  /// denies the loyalty write (42501).
  Future<void> grantManualReward(String phone, ManualRewardInput reward);

  /// Same contract as the staff board's registerVisit: the visit row is the
  /// source of truth, the stamp attempt degrades to pending instead of failing.
  Future<VisitRecorded> registerVisit(CheckInInput input);

  /// `staff_log` rows for this phone, newest first.
  Future<List<StaffActivity>> activityLog(String phone);
}

class SupabaseCustomerLookupRepo implements CustomerLookupRepo {
  SupabaseCustomerLookupRepo(this._db);

  final CustomerLookupDb _db;

  static int _intOf(Object? value) => value is num ? value.toInt() : 0;

  @override
  Future<List<CustomerHit>> search(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const [];
    final normalized = normalizeSearchTerm(trimmed);
    if (normalized.isEmpty) return const [];
    final rows = await _db.searchCustomers('%$normalized%', '%$trimmed%');
    return [
      for (final row in rows) CustomerHit.fromRow(row),
    ];
  }

  @override
  Future<CustomerProfile> loadProfile(String phone) async {
    final customer = await _db.fetchCustomer(phone);
    final loyalty = await _db.fetchLoyalty(phone);
    final orders = await _db.fetchRecentOrders(phone, 5);
    final visits = await _db.fetchVisitsCount(phone);
    return CustomerProfile(
      phone: customer?['phone'] as String? ?? phone,
      name: (customer?['name'] as String?) ?? '',
      points: _intOf(loyalty?['points']),
      lifetimePoints: _intOf(loyalty?['lifetime_points']),
      stamps: _intOf(loyalty?['stamps']),
      visits: visits,
      recentOrders: [
        for (final row in orders) LookupOrder.fromRow(row),
      ],
    );
  }

  @override
  Future<void> grantManualReward(
    String phone,
    ManualRewardInput reward,
  ) async {
    // 1. Current row feeds the patch (append vouchers / add points).
    final current = await _db.fetchLoyalty(phone);
    // 2. The UPDATE itself is the permission boundary — 42501 surfaces typed
    //    (wrapped here so fake seams map identically to the Supabase adapter).
    try {
      await _db.updateLoyalty(
        phone,
        manualRewardLoyaltyPatch(current, reward),
      );
    } on PostgrestException catch (error) {
      rethrowAsTyped(error);
    }
    // 3. Audit trail is best-effort; never block the grant UX on it.
    try {
      await _db.insertStaffLog(manualRewardStaffLogRow(phone, reward));
    } catch (_) {}
  }

  @override
  Future<VisitRecorded> registerVisit(CheckInInput input) async {
    // 1. The visit itself is the source of truth — permission failures here
    //    are real failures and surface typed (42501 → StaffPermissionException).
    await _db.insertVisit(checkInVisitRow(input));

    // 2. Audit trail is best-effort; never block the check-in UX on it.
    try {
      await _db.insertStaffLog(checkInStaffLogRow(input));
    } catch (_) {}

    // 3. Direct loyalty stamp attempt — typically blocked by loyalty_state
    //    own-row RLS (staff ≠ row owner) until a server-side path exists;
    //    ANY failure here degrades to loyaltyPending instead of an error.
    var loyaltyPending = false;
    try {
      final threshold =
          await _db.fetchStampMinSpend() ?? stampMinSpendDefaultEgp;
      if (input.spendEgp >= threshold) {
        final current = await _db.fetchStamps(input.phone);
        if (current == null) {
          loyaltyPending = true; // row not visible — cannot verify
        } else {
          await _db.updateStamps(input.phone, current + 1);
        }
      }
    } on Exception {
      loyaltyPending = true;
    }
    return VisitRecorded(loyaltyPending: loyaltyPending);
  }

  @override
  Future<List<StaffActivity>> activityLog(String phone) async {
    final rows = await _db.fetchStaffLog(phone, 20);
    return [
      for (final row in rows) StaffActivity.fromRow(row),
    ];
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final customerLookupRepoProvider = Provider<CustomerLookupRepo>(
  (ref) => SupabaseCustomerLookupRepo(SupabaseCustomerLookupDb(supabase)),
);

final recentSearchesProvider = FutureProvider<RecentSearchStore>(
  (ref) async => RecentSearchStore(await SharedPreferences.getInstance()),
);
