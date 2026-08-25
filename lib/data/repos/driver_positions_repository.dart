import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';

abstract class DriverPositionsGateway {
  Future<void> upsertPosition({
    required String driverId,
    required String orderId,
    required double lat,
    required double lng,
  });
  String? get currentUserId;
}

class SupabaseDriverPositionsGateway implements DriverPositionsGateway {
  const SupabaseDriverPositionsGateway(this._client);
  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> upsertPosition({
    required String driverId,
    required String orderId,
    required double lat,
    required double lng,
  }) async {
    await _client.from('driver_positions').upsert({
      'driver_id': driverId,
      'order_id': orderId,
      'lat': lat,
      'lng': lng,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

final driverPositionsGatewayProvider = Provider<DriverPositionsGateway>(
  (ref) => SupabaseDriverPositionsGateway(supabase),
);
