// Shared phone resolver — deduplicates _phoneOf/_phoneFor across
// CustomersRepo and OrdersRepo (ARCH-03). Single source of truth for
// resolving a Customer's canonical phone (+20XXXXXXXXXX) from their
// google_user_id.

import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves phone for [googleUserId] via `customers` table, or null if no row.
/// Single RTT — mirrors SupabaseCustomersRepo._phoneFor but nullable.
Future<String?> resolvePhone(SupabaseClient client, String googleUserId) async {
  final row = await client
      .from('customers')
      .select('phone')
      .eq('google_user_id', googleUserId)
      .maybeSingle();
  return row?['phone'] as String?;
}

/// Resolves phone or throws StateError if no customer row exists.
/// For write paths that must have a phone (e.g., addAddress).
Future<String> requirePhone(SupabaseClient client, String googleUserId) async {
  final phone = await resolvePhone(client, googleUserId);
  if (phone == null || phone.isEmpty) {
    throw StateError('no customer row for google_user_id $googleUserId');
  }
  return phone;
}
