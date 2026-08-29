// Profile role gateway — domain-owned interface for authoritative role fetch.
// Server (`profiles.role`) is source of truth; local SharedPreferences is cache.
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ProfileRoleGateway {
  /// Returns raw role string (`customer|staff|driver|admin`) or null.
  Future<String?> fetchRole(String userId);
}

class _NoopProfileGateway implements ProfileRoleGateway {
  @override
  Future<String?> fetchRole(String userId) async => null;
}

final profileRoleGatewayProvider = Provider<ProfileRoleGateway>(
  (ref) => _NoopProfileGateway(),
);
