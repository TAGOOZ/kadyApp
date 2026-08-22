// Customers repository — Supabase-backed access to public.customers.
// Phone is the canonical Customer key (ADR-0007); google_user_id links 1:1.
// Slice #011 extends this file with profile updates + address CRUD
// (CustomerProfileRepo); RLS own-row guards apply via google_user_id.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import 'address.dart';

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
  });
  Future<AddressRecord> updateAddress({required AddressRecord address});
  Future<void> deleteAddress({required String addressId});
}

class SupabaseCustomerProfileRepo implements CustomerProfileRepo {
  /// Own phone resolved from the customers row — mirrors how #004 looks up
  /// by google_user_id; addresses are then queried by that phone key.
  Future<String> _phoneFor(String googleUserId) async {
    final rows = await supabase
        .from('customers')
        .select('phone')
        .eq('google_user_id', googleUserId)
        .limit(1);
    if (rows.isEmpty) {
      throw StateError('no customer row for google_user_id $googleUserId');
    }
    return (rows.first as Map)['phone'] as String;
  }

  @override
  Future<CustomerRecord> loadByGoogleUserId(String googleUserId) async {
    final row = await supabase
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
    final row = await supabase
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
    final phone = await _phoneFor(googleUserId);
    final rows = await supabase
        .from('addresses')
        .select()
        .eq('phone', phone)
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
  }) async {
    final phone = await _phoneFor(googleUserId);
    final row = await supabase.from('addresses').insert({
      'phone': phone,
      'label': label.key,
      'address_text': addressText.trim(),
    }).select().single();
    return AddressRecord.fromRow(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<AddressRecord> updateAddress({
    required AddressRecord address,
  }) async {
    final row = await supabase
        .from('addresses')
        .update({
          'label': address.label.key,
          'address_text': address.addressText.trim(),
        })
        .eq('id', address.id)
        .select()
        .single();
    return AddressRecord.fromRow(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<void> deleteAddress({required String addressId}) async {
    await supabase.from('addresses').delete().eq('id', addressId);
  }
}

final customersRepoProvider = Provider<CustomersRepo>(
  (ref) => SupabaseCustomersRepo(),
);

final customerProfileRepoProvider = Provider<CustomerProfileRepo>(
  (ref) => SupabaseCustomerProfileRepo(),
);
