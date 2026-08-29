// ignore_for_file: use_null_aware_elements
// Customers repository — Supabase-backed access to public.customers.
// Phone is the canonical Customer key (ADR-0007); google_user_id links 1:1.
// Slice #011 extends this file with profile updates + address CRUD
// (CustomerProfileRepo); RLS own-row guards apply via google_user_id.
// Domain owns CustomersRepo interface + record types (DAG); this file provides
// Supabase adapter and re-exports domain types for backwards compat.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/customer_gateway.dart';
import 'address.dart';
import 'customer_phone_resolver.dart';

export '../../domain/customer_gateway.dart'
    show CustomerRecord, CustomerUpsert, PhoneAlreadyLinkedException, CustomersRepo, customersRepoProvider;

class SupabaseCustomersRepo implements CustomersRepo {
  SupabaseCustomersRepo(this._client);
  final SupabaseClient _client;

  @override
  Future<CustomerRecord?> findByGoogleUserId(String googleUserId) async {
    final row = await _client
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
      final row = await _client
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
    return _customerFromRow(row);
  }
}

CustomerRecord _customerFromRow(Map<String, dynamic> row) {
  final birthdate = row['birthdate'] as String?;
  return CustomerRecord(
    phone: row['phone'] as String,
    name: row['name'] as String? ?? '',
    email: row['email'] as String?,
    birthdate: birthdate == null || birthdate.isEmpty
        ? null
        : DateTime.tryParse(birthdate),
    isStudent: (row['is_student'] as bool?) ?? false,
    city: row['city'] as String?,
  );
}

/// Partial profile update — null fields stay untouched on the customers row.
class CustomerPatch {
  const CustomerPatch({
    this.name,
    this.email,
    this.birthdate,
    this.isStudent,
    this.city,
  });

  final String? name;
  final String? email;
  final DateTime? birthdate;
  final bool? isStudent;
  final String? city;

  Map<String, dynamic> toRow() => {
        if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
        if (email != null)
          'email': email!.trim().isEmpty ? null : email!.trim(),
        if (birthdate != null)
          'birthdate': birthdate!.toIso8601String().substring(0, 10),
        if (isStudent != null) 'is_student': isStudent,
        if (city != null) 'city': city!.trim().isEmpty ? null : city!.trim(),
      };
}

/// Profile + saved-addresses access for the signed-in Customer.
/// RLS (ADR-0007) restricts every write to `google_user_id = auth.uid()`.
abstract class CustomerProfileRepo {
  Future<CustomerRecord> loadByGoogleUserId(String googleUserId);
  Future<CustomerRecord> updateProfile({
    required String phone,
    required CustomerPatch patch,
  });
  Future<List<AddressRecord>> listAddresses({required String googleUserId});
  Future<AddressRecord> addAddress({
    required String googleUserId,
    required AddressLabel label,
    required String addressText,
    double? latitude,
    double? longitude,
  });
  Future<AddressRecord> updateAddress({required AddressRecord address});
  Future<void> deleteAddress({required String addressId});
}

class SupabaseCustomerProfileRepo implements CustomerProfileRepo {
  SupabaseCustomerProfileRepo(this._client);
  final SupabaseClient _client;

  /// Own phone resolved from the customers row — now via shared resolver (ARCH-03)
  Future<String> _phoneFor(String googleUserId) async =>
      requirePhone(_client, googleUserId);

  @override
  Future<CustomerRecord> loadByGoogleUserId(String googleUserId) async {
    final row = await _client
        .from('customers')
        .select()
        .eq('google_user_id', googleUserId)
        .maybeSingle();
    if (row == null) {
      throw StateError('no customer row for google_user_id $googleUserId');
    }
    return _customerFromRow(row);
  }

  @override
  Future<CustomerRecord> updateProfile({
    required String phone,
    required CustomerPatch patch,
  }) async {
    final row = await _client
        .from('customers')
        .update(patch.toRow())
        .eq('phone', phone)
        .select()
        .single();
    return _customerFromRow(row);
  }

  @override
  Future<List<AddressRecord>> listAddresses({
    required String googleUserId,
  }) async {
    final rows = await _client
        .from('addresses')
        .select(
          'id, phone, label, address_text, latitude, longitude, updated_at, customers!inner(google_user_id)',
        )
        .eq('customers.google_user_id', googleUserId)
        .order('created_at', ascending: true);
    return rows
        .map((row) => AddressRecord.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Future<AddressRecord> addAddress({
    required String googleUserId,
    required AddressLabel label,
    required String addressText,
    double? latitude,
    double? longitude,
  }) async {
    final phone = await _phoneFor(googleUserId);
    final row = await _client.from('addresses').insert({
      'phone': phone,
      'label': label.key,
      'address_text': addressText.trim(),
      if (latitude case final v?) 'latitude': v,
      if (longitude case final v?) 'longitude': v,
    }).select().single();
    return AddressRecord.fromRow(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<AddressRecord> updateAddress({
    required AddressRecord address,
  }) async {
    final row = await _client
        .from('addresses')
        .update({
          'label': address.label.key,
          'address_text': address.addressText.trim(),
          if (address.latitude case final v?) 'latitude': v,
          if (address.longitude case final v?) 'longitude': v,
        })
        .eq('id', address.id)
        .select()
        .single();
    return AddressRecord.fromRow(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<void> deleteAddress({required String addressId}) async {
    await _client.from('addresses').delete().eq('id', addressId);
  }
}

final customerProfileRepoProvider = Provider<CustomerProfileRepo>(
  (ref) => SupabaseCustomerProfileRepo(supabase),
);
