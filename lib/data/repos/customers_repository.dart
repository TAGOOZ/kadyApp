// Customers repository — Supabase-backed access to public.customers.
// Phone is the canonical Customer key (ADR-0007); google_user_id links 1:1.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';

class CustomerRecord {
  const CustomerRecord({
    required this.phone,
    required this.name,
    this.email,
  });

  final String phone;
  final String name;
  final String? email;
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

class SupabaseCustomersRepo implements CustomersRepo {
  @override
  Future<CustomerRecord?> findByGoogleUserId(String googleUserId) async {
    final row = await supabase
        .from('customers')
        .select()
        .eq('google_user_id', googleUserId)
        .maybeSingle();
    if (row == null) return null;
    return _fromRow(row);
  }

  @override
  Future<CustomerRecord> upsert(CustomerUpsert customer) async {
    try {
      final row = await supabase
          .from('customers')
          .upsert(customer.toRow(), onConflict: 'phone')
          .select()
          .single();
      return _fromRow(row);
    } on PostgrestException catch (error) {
      if (error.code == '23505') throw const PhoneAlreadyLinkedException();
      rethrow;
    }
  }

  CustomerRecord _fromRow(Map<String, dynamic> row) {
    return CustomerRecord(
      phone: row['phone'] as String,
      name: row['name'] as String,
      email: row['email'] as String?,
    );
  }
}

final customersRepoProvider = Provider<CustomersRepo>(
  (ref) => SupabaseCustomersRepo(),
);
