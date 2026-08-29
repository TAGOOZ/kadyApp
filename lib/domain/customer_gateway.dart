// Customer identity gateway — domain-owned interface for Customer ↔ phone mapping.
// Phone is the canonical Customer key (CONTEXT.md, ADR-0007). Domain owns the
// interface; data provides Supabase adapter so auth_controller never imports data.
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomerRecord {
  const CustomerRecord({
    required this.phone,
    required this.name,
    this.email,
    this.birthdate,
    this.isStudent = false,
    this.city,
  });

  final String phone;
  final String name;
  final String? email;
  final DateTime? birthdate;
  final bool isStudent;
  final String? city;
}

class CustomerUpsert {
  const CustomerUpsert({
    required this.phone,
    required this.googleUserId,
    required this.name,
    this.email,
    this.isStudent = false,
    this.birthdate,
    this.city,
  });

  final String phone;
  final String googleUserId;
  final String name;
  final String? email;
  final bool isStudent;
  final DateTime? birthdate;
  final String? city;

  Map<String, dynamic> toRow() {
    return {
      'phone': phone,
      'google_user_id': googleUserId,
      'name': name,
      if (email != null && email!.isNotEmpty) 'email': email,
      'is_student': isStudent,
      if (birthdate != null)
        'birthdate': birthdate!.toIso8601String().substring(0, 10),
      if (city != null && city!.isNotEmpty) 'city': city,
    };
  }
}

/// Postgres unique_violation (23505) on customers_pkey or
/// customers_google_user_id_key — the phone/identity pair is taken.
class PhoneAlreadyLinkedException implements Exception {
  const PhoneAlreadyLinkedException();
}

abstract class CustomersRepo {
  Future<CustomerRecord?> findByGoogleUserId(String googleUserId);
  Future<CustomerRecord> upsert(CustomerUpsert customer);
}

class _NoopCustomersRepo implements CustomersRepo {
  @override
  Future<CustomerRecord?> findByGoogleUserId(String googleUserId) async => null;
  @override
  Future<CustomerRecord> upsert(CustomerUpsert customer) async =>
      CustomerRecord(phone: customer.phone, name: customer.name, email: customer.email);
}

final customersRepoProvider = Provider<CustomersRepo>(
  (ref) => _NoopCustomersRepo(),
);
