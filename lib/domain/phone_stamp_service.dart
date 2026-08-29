// Shared stamp + phone seam — single port for staff/lookup/driver.
// Collapses triplicated fetchCustomersByPhones/applyStampRpc/fetchStampMinSpend
// into one domain interface with two adapters (Supabase + Fake).
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Server-authoritative stamp via `staff_apply_stamp` RPC (migration 0004).
abstract class PhoneStampService {
  /// Calls `staff_apply_stamp` security-definer RPC.
  Future<bool?> applyStamp(String phone, int spend);

  /// Admin-editable stamp threshold (app_config `stamp_min_spend`).
  Future<int?> fetchStampMinSpend();
}

/// Phone → name bulk lookup (bounded, distinct phones from current page).
abstract class CustomerPhoneResolver {
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(Set<String> phones);
}

/// Combined port used by staff/lookup/driver — single applyStamp + phoneResolver.
abstract class CustomerLoyaltyOps implements PhoneStampService, CustomerPhoneResolver {}

class _NoopPhoneStampService implements PhoneStampService {
  @override
  Future<bool?> applyStamp(String phone, int spend) async => null;
  @override
  Future<int?> fetchStampMinSpend() async => null;
}

class _NoopCustomerPhoneResolver implements CustomerPhoneResolver {
  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(Set<String> phones) async => const [];
}

class _NoopCustomerLoyaltyOps implements CustomerLoyaltyOps {
  @override
  Future<bool?> applyStamp(String phone, int spend) async => null;
  @override
  Future<int?> fetchStampMinSpend() async => null;
  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(Set<String> phones) async => const [];
}

final phoneStampServiceProvider = Provider<PhoneStampService>(
  (ref) => _NoopPhoneStampService(),
);

final customerPhoneResolverProvider = Provider<CustomerPhoneResolver>(
  (ref) => _NoopCustomerPhoneResolver(),
);

final customerLoyaltyOpsProvider = Provider<CustomerLoyaltyOps>(
  (ref) => _NoopCustomerLoyaltyOps(),
);
