// Supabase adapter for DriverProfileGateway — domain owns interface.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/driver_gateway.dart';

class SupabaseDriverProfileGateway implements DriverProfileGateway {
  SupabaseDriverProfileGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<String?> fetchDriverDisplayName() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('role')
          .eq('user_id', uid)
          .eq('role', 'driver')
          .maybeSingle();
      if (row == null) return null;
      final name = row['display_name'] as String?;
      if (name == null || name.trim().isEmpty) return null;
      return name.trim();
    } catch (_) {
      return null;
    }
  }
}

/// Factory for main.dart wiring.
DriverProfileGateway createSupabaseDriverGateway() {
  try {
    return SupabaseDriverProfileGateway(supabase);
  } catch (_) {
    return _NoopDriverGateway();
  }
}

class _NoopDriverGateway implements DriverProfileGateway {
  @override
  Future<String?> fetchDriverDisplayName() async => null;
}
