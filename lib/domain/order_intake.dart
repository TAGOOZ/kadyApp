// lib/domain/order_intake.dart — Deep Order Intake module (Candidate 6)
//
// Single content-addressed key = hash(phone + items + address) stable across
// retries (no nonce), explicit DAG not alphabetical names.
//
// Interface: place(OrderDraft) -> PlacedOrder with single idempotency key.
// Leverage: one hash hides canonicalization + sorting; one pipeline hides
// validate -> risk -> rate-limit -> dedup explicit ordering.
// Locality: trigger order change in one place (order_intake_pipeline), hash
// changes in one pure function.
// Seam: OrdersRepo with two adapters — Supabase Postgres in prod
// (order_intake_pipeline trigger) and in-memory FakeOrdersDb in tests.
// Keeps risk/pricing deepened (0027/28/29) — reuses risk_calculate + pricing
// quote inside pipeline, doesn't duplicate rule math.
//
// Canonical encoding (Dart + Postgres must match):
//   canonical = phoneOrGoogleId + '|' + sortedItemKeys(+ '|' + addressId)
//   itemKey = id:qty:size:sugar:addonsSorted:note  (unit_total excluded —
//   dedup on intent, not computed price; price change between retries still dedupes)
//   items sorted lexicographically, addons sorted, phone/note trimmed.
//   Hash = md5(canonical) hex.
//   Stable across retries, different address -> different hash, json key order
//   insensitive.
//
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'menu_models.dart';

/// Payload for order items — canonical domain type used by both
/// `orderIntakeKey` and `SupabaseOrdersRepo`. Lives in domain so the hash
/// canonicalization stays pure and SQL-parity is testable without Supabase.
/// Data layer re-exports this for backwards compat (`data/models/menu_models`).
class IntakeItemPayload {
  const IntakeItemPayload({
    required this.id,
    required this.nameAr,
    required this.qty,
    required this.unitTotalEgp,
    required this.config,
  });

  final String id;
  final String nameAr;
  final int qty;
  final int unitTotalEgp;
  final ItemConfig config;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name_ar': nameAr,
        'qty': qty,
        'unit_total': unitTotalEgp,
        'config': {
          'size': config.sizeIndex,
          'sugar': config.sugarIndex,
          'addons': config.addons.toList()..sort(),
          if (config.note != null && config.note!.trim().isNotEmpty)
            'note': config.note,
        },
      };
}

/// Canonical order intake key — content-addressed, stable across retries.
///
/// Mirrors `public.compute_order_intake_hash(phone, items, address_id)` in
/// SQL (0030_intake_pipeline.sql). Keep them identical.
///
/// - `phone` preferred; when null, `googleUserId` fallback is used so
///   Google-only guests still get stable dedup (phone is business key).
/// - `items` are the intake payload list; we canonicalize via field
///   extraction + sorting, not via `jsonEncode`/`jsonb::text` ordering.
/// - `addressId` distinguishes delivery destinations (null for dine-in/pickup).
String orderIntakeKey({
  String? phone,
  String? googleUserId,
  required List<IntakeItemPayload> items,
  String? addressId,
}) {
  final effectivePhone = (phone != null && phone.trim().isNotEmpty)
      ? phone.trim()
      : (googleUserId?.trim() ?? '');

  final itemKeys = <String>[];
  for (final item in items) {
    final id = item.id;
    final qty = item.qty.toString();
    final size = item.config.sizeIndex.toString();
    final sugar = item.config.sugarIndex.toString();
    final addonsSorted = (item.config.addons.toList()..sort()).join(',');
    final note = (item.config.note ?? '').trim();
    itemKeys.add('$id:$qty:$size:$sugar:$addonsSorted:$note');
  }
  itemKeys.sort();
  final itemsCanonical = itemKeys.join('|');
  final canonical = '$effectivePhone|$itemsCanonical|${addressId ?? ''}';
  return md5.convert(utf8.encode(canonical)).toString();
}

/// Raw JSON variant — for SQL parity and for callers that already have
/// `List<Map<String,dynamic>>` from `OrderItemPayload.toJson()`. Keeps SQL
/// `public.compute_order_intake_hash(phone, items, address_id)` identical.
String orderIntakeKeyFromJson({
  String? phone,
  String? googleUserId,
  required List<Map<String, dynamic>> itemsJson,
  String? addressId,
}) {
  final effectivePhone = (phone != null && phone.trim().isNotEmpty)
      ? phone.trim()
      : (googleUserId?.trim() ?? '');

  final itemKeys = <String>[];
  for (final raw in itemsJson) {
    final id = raw['id']?.toString() ?? '';
    final qty = raw['qty']?.toString() ?? '1';
    final config = raw['config'] as Map<String, dynamic>? ?? {};
    final size = config['size']?.toString() ?? '0';
    final sugar = config['sugar']?.toString() ?? '0';
    final addonsRaw = config['addons'] as List? ?? [];
    final addonsSorted =
        (addonsRaw.map((e) => e.toString()).toList()..sort()).join(',');
    final note = config['note']?.toString().trim() ?? '';
    itemKeys.add('$id:$qty:$size:$sugar:$addonsSorted:$note');
  }
  itemKeys.sort();
  final itemsCanonical = itemKeys.join('|');
  final canonical = '$effectivePhone|$itemsCanonical|${addressId ?? ''}';
  return md5.convert(utf8.encode(canonical)).toString();
}
