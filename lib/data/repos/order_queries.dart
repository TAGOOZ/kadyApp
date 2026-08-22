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
