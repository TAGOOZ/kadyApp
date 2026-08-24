// Driver identity provider — real name from Supabase profiles.display_name
// where user_id==auth.uid() and role==driver. Returns null when missing,
// empty or on error so the UI layer can fallback to DriverStrings.driverNameStub
// (ADR-0004 layer-first: data never imports l10n/ui).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repos/driver_orders_repository.dart';

/// Real driver identity from `profiles.display_name`; `null` signals the UI
/// to render [DriverStrings.driverNameStub]. Loading/error also fall back
/// to stub so the AppBar never blanks (task spec: loading shows stub).
final driverProfileProvider = FutureProvider<String?>((ref) async {
  final repo = ref.watch(driverOrdersRepoProvider);
  try {
    final name = await repo.fetchDriverDisplayName();
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return null;
  } catch (_) {
    return null;
  }
});
