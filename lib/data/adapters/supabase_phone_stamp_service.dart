// Single Supabase implementation for phone/stamp seams.
// Collapses triplicated fetchCustomersByPhones / applyStampRpc / fetchStampMinSpend
// from StaffOrdersDb, CustomerLookupDb, DriverOrdersDb into one adapter.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/phone_stamp_service.dart';

class SupabasePhoneStampService implements PhoneStampService {
  SupabasePhoneStampService(this._client);
  final SupabaseClient _client;

  @override
  Future<bool?> applyStamp(String phone, int spend) async {
    try {
      return await _client.rpc('staff_apply_stamp', params: {'p_phone': phone, 'p_spend': spend});
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int?> fetchStampMinSpend() async {
    try {
      final row = await _client.from('app_config').select('value').eq('key', 'stamp_min_spend').maybeSingle();
      final v = row?['value'];
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
    } catch (_) {
      return null;
    }
    return null;
  }
}

class SupabaseCustomerPhoneResolver implements CustomerPhoneResolver {
  SupabaseCustomerPhoneResolver(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(Set<String> phones) async {
    if (phones.isEmpty) return const [];
    final rows = await _client.from('customers').select('phone, name').inFilter('phone', phones.toList());
    return List<Map<String, dynamic>>.from(rows as List);
  }
}

class SupabaseCustomerLoyaltyOps implements CustomerLoyaltyOps {
  SupabaseCustomerLoyaltyOps(SupabaseClient client)
      : _stamp = SupabasePhoneStampService(client),
        _resolver = SupabaseCustomerPhoneResolver(client);
  final SupabasePhoneStampService _stamp;
  final SupabaseCustomerPhoneResolver _resolver;

  @override
  Future<bool?> applyStamp(String phone, int spend) => _stamp.applyStamp(phone, spend);

  @override
  Future<int?> fetchStampMinSpend() => _stamp.fetchStampMinSpend();

  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(Set<String> phones) =>
      _resolver.fetchCustomersByPhones(phones);
}

/// Factories for main.dart wiring.
PhoneStampService createSupabasePhoneStampService() => SupabasePhoneStampService(supabase);
CustomerPhoneResolver createSupabasePhoneResolver() => SupabaseCustomerPhoneResolver(supabase);
CustomerLoyaltyOps createSupabaseCustomerLoyaltyOps() => SupabaseCustomerLoyaltyOps(supabase);
