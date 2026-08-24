// Profile role gateway — authoritative role from `public.profiles`.
// Server is source of truth; local `SharedPreferences` is only a cache
// synced after auth. Prevents fake `admin` via local switcher alone.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';

abstract class ProfileRoleGateway {
  /// Returns raw role string (`customer|staff|driver|admin`) or null.
  Future<String?> fetchRole(String userId);
}

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

final profileRoleGatewayProvider = Provider<ProfileRoleGateway>(
  (ref) {
    try {
      return SupabaseProfileRoleGateway(supabase);
    } catch (_) {
      return _NoopProfileRoleGateway();
    }
  },
);
