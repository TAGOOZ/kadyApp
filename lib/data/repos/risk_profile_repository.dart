// Risk profile + risk events seam — RISK-02 (issue #47).
// Phone is the canonical Customer key (CONTEXT.md).
// Counters are server-authoritative: mutated only via SECURITY DEFINER
// trigger sync_risk_profile(); this seam is read-only (select).
// Events ledger is append-only via trigger; clients never INSERT directly
// (no RLS INSERT policy — unauthenticated insert fails 42501).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/risk_profile.dart';

/// Read-only access to `customer_risk_profiles` + `risk_events`.
/// Used by future admin UI (RISK-06) but queryable now.
abstract class RiskProfileRepo {
  /// Fetch the aggregated profile for [phone]. Returns null when the customer
  /// has no profile row yet (should not happen — handle_new_customer trigger
  /// backfills, but defensive for pre-0018 data).
  Future<RiskProfile?> fetchProfile(String phone);

  /// Recent ledger events for [phone], newest first.
  Future<List<RiskEvent>> fetchRecentEvents(
    String phone, {
    int limit = 20,
  });
}

class SupabaseRiskProfileRepo implements RiskProfileRepo {
  SupabaseRiskProfileRepo(this._client);

  final SupabaseClient _client;

  @override
  Future<RiskProfile?> fetchProfile(String phone) async {
    final row = await _client
        .from('customer_risk_profiles')
        .select()
        .eq('phone', phone)
        .maybeSingle();
    if (row == null) return null;
    try {
      return RiskProfile.fromRow(Map<String, dynamic>.from(row as Map));
    } on ArgumentError {
      // Malformed row (e.g. empty phone) — surface as missing rather than crash UI.
      return null;
    }
  }

  @override
  Future<List<RiskEvent>> fetchRecentEvents(
    String phone, {
    int limit = 20,
  }) async {
    final rows = await _client
        .from('risk_events')
        .select()
        .eq('phone', phone)
        .order('created_at', ascending: false)
        .limit(limit);
    final parsed = <RiskEvent>[];
    for (final r in List<Map<String, dynamic>>.from(rows as List)) {
      try {
        parsed.add(RiskEvent.fromRow(r));
      } on ArgumentError {
        // Skip corrupt ledger rows instead of failing the whole fetch.
        continue;
      }
    }
    return parsed;
  }
}

/// In-memory fake for widget/unit tests — no network, no Supabase.
/// Mirrors the seam so tests stay offline and deterministic.
class FakeRiskProfileRepo implements RiskProfileRepo {
  FakeRiskProfileRepo({
    Map<String, RiskProfile>? profiles,
    Map<String, List<RiskEvent>>? events,
  })  : _profiles = profiles ?? {},
        _events = events ?? {};

  final Map<String, RiskProfile> _profiles;
  final Map<String, List<RiskEvent>> _events;

  void seedProfile(RiskProfile profile) {
    _profiles[profile.phone] = profile;
  }

  void seedEvents(String phone, List<RiskEvent> events) {
    _events[phone] = List<RiskEvent>.from(events);
  }

  @override
  Future<RiskProfile?> fetchProfile(String phone) async => _profiles[phone];

  @override
  Future<List<RiskEvent>> fetchRecentEvents(
    String phone, {
    int limit = 20,
  }) async {
    final list = _events[phone] ?? const <RiskEvent>[];
    // Newest first as stored; emulate DB ordering by created_at desc.
    final sorted = List<RiskEvent>.from(list)
      ..sort((a, b) {
        final ac = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bc = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bc.compareTo(ac);
      });
    if (sorted.length <= limit) return sorted;
    return sorted.sublist(0, limit);
  }
}

final riskProfileRepoProvider = Provider<RiskProfileRepo>(
  (ref) => SupabaseRiskProfileRepo(supabase),
);
