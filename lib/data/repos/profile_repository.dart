// Profile role gateway — Supabase adapter for domain ProfileRoleGateway.
// Domain owns the interface (lib/domain/profile_gateway.dart); this file owns Supabase.
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/profile_gateway.dart';

export '../../domain/profile_gateway.dart' show ProfileRoleGateway, profileRoleGatewayProvider;

class SupabaseProfileRoleGateway implements ProfileRoleGateway {
  SupabaseProfileRoleGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> fetchRole(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();
      return row?['role'] as String?;
    } catch (_) {
      return null;
    }
  }
}

class _NoopProfileRoleGateway implements ProfileRoleGateway {
  @override
  Future<String?> fetchRole(String userId) async => null;
}

/// Helper to create prod gateway safely (used in main.dart overrides).
ProfileRoleGateway createSupabaseProfileGateway() {
  try {
    return SupabaseProfileRoleGateway(supabase);
  } catch (_) {
    return _NoopProfileRoleGateway();
  }
}
