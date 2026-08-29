// Driver profile gateway — domain-owned interface for driver identity.
// Data provides SupabaseDriverProfileGateway; domain provider is pure.
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class DriverProfileGateway {
  /// Returns display_name for driver or null → UI falls back to stub.
  Future<String?> fetchDriverDisplayName();
}

class _NoopDriverGateway implements DriverProfileGateway {
  @override
  Future<String?> fetchDriverDisplayName() async => null;
}

final driverProfileGatewayProvider = Provider<DriverProfileGateway>(
  (ref) => _NoopDriverGateway(),
);
