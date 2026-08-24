// Read-only order probes for the home hub (#005) — the live order timeline
// and mutations stay owned by orders_repository.dart (#006). RLS restricts
// every probe to the caller's own rows; failures degrade to an empty list.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_config.dart';

/// Seam so widgets/tests never touch the network directly.
typedef FetchActiveOrders = Future<List<Map<String, dynamic>>> Function(
    String phone);

/// In-flight orders for a Customer phone: newest first, max 3, excluding
/// terminal statuses (`done`/`cancelled`). Columns mirror the strip's needs.
Future<List<Map<String, dynamic>>> fetchActive(String phone) async {
  try {
    final rows = await supabase
        .from('orders')
        .select('id, display_number, status, mode')
        .eq('phone', phone)
        .not('status', 'in', '(done,cancelled)')
        .order('created_at', ascending: false)
        .limit(3);
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  } catch (_) {
    // Offline/guest hiccup — the hub simply hides the strip (standard policy).
    return const [];
  }
}

final activeOrdersFetcherProvider =
    Provider<FetchActiveOrders>((ref) => fetchActive);

/// Seam for the home order-again strip.
typedef FetchLastCompletedOrder = Future<Map<String, dynamic>?> Function(
    String phone);

/// Most recent completed Order for a Customer phone (read-only probe):
/// `{id, display_number, items, total}` or null when none/offline. `items`
/// jsonb mirrors orders_repository.dart:164 — `{name_ar, qty, unit_total…}`.
Future<Map<String, dynamic>?> fetchLastCompleted(String phone) async {
  try {
    final rows = await supabase
        .from('orders')
        .select('id, display_number, items, total')
        .eq('phone', phone)
        .eq('status', 'done')
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first as Map);
  } catch (_) {
    // Offline/guest hiccup — the hub simply hides the strip (standard policy).
    return null;
  }
}

final lastCompletedOrderFetcherProvider =
    Provider<FetchLastCompletedOrder>((ref) => fetchLastCompleted);
