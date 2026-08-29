// ignore_for_file: use_null_aware_elements
// Orders slice data layer (issue #003): Supabase-backed orders/addresses
// access plus the pure checkout math — points preview (round half-up with
// dine-in ×1.1), totals with flat delivery fee, and Africa/Cairo half-hour
// pickup slots emitted as UTC instants (ADR-0009). All supabase calls sit
// behind the OrdersRepo seam so tests never hit the network.
//
// Order Intake deep module (Candidate 6): single content-addressed key =
// hash(phone + items + address) stable across retries (no nonce), explicit
// DAG via order_intake_pipeline() (validate → risk → rate-limit → dedup).
// Duplicate suppression is content-addressed (60s window, server hash via
// compute_order_intake_hash) — no Uuid.v4 nonce, no triple fallback.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../domain/order_intake.dart' as intake;
import '../../domain/pricing.dart';
import '../../domain/risk_engine.dart';
import '../../domain/risk_profile.dart';
import '../models/menu_models.dart';
import 'customer_phone_resolver.dart';
import 'risk_engine_provider.dart';

// ---------------------------------------------------------------------------
// Service mode + loyalty math (FEATURES §3.5, §4, §11)
// ---------------------------------------------------------------------------

enum OrderMode { dineIn, pickup, delivery }

extension OrderModeWire on OrderMode {
  /// DB check-constraint vocabulary (`orders.mode`).
  String get wireName => switch (this) {
        OrderMode.dineIn => 'dine_in',
        OrderMode.pickup => 'pickup',
        OrderMode.delivery => 'delivery',
      };

  /// ~10 min for صالة/استلام · ~30 min توصيل.
  int get etaMinutes => this == OrderMode.delivery ? 30 : 10;
}

const defaultDeliveryFeeEgp = kPricingDefaultDeliveryFeeEgp; // §11.7 — canonical in pricing.dart (deep module).
const dineInMultiplier = 1.1; // §4 — canonical in pricing.dart/loyalty_rules.dart.
const egpPerPoint = kPricingEgpPerPoint; // §4 — canonical in pricing.dart.

/// Round half-up applied to the FINAL earned value, after multipliers (§4):
/// 95 EGP → 9.5 pts → 10 pts; dine-in 90 EGP → 9 × 1.1 = 9.9 → 10 pts.
/// Delegates to Pricing deep module so preview == server validation.
int roundHalfUp(double value) => pricingRoundHalfUp(value);

/// Delivery pays the flat fee; صالة/استلام pay nothing (fee row hidden).
/// Delegates to Pricing deep module (FeeTable).
int deliveryFeeFor(OrderMode mode, {int configuredFeeEgp = defaultDeliveryFeeEgp}) {
  return pricingDeliveryFeeFor(
    isDelivery: mode == OrderMode.delivery,
    configuredFeeEgp: configuredFeeEgp,
  );
}

int totalOf({required int subtotalEgp, required int deliveryFeeEgp}) {
  return pricingTotalOf(
    subtotalEgp: subtotalEgp,
    deliveryFeeEgp: deliveryFeeEgp,
  );
}

/// Deprecated: preview diverged from canonical rule when doubleWindow or
/// custom pointsPer10 is active (preview 10 vs earnedFor 20). Kept for
/// backwards compat; new code should use [earnedFor] from loyalty_rules.dart
/// (ARCH-06). This still does roundHalfUp with dine-in multiplier for
/// offline preview (no doubleWindow).
@Deprecated('Use earnedFor from loyalty_rules.dart')
int pointsPreviewFor({required int subtotalEgp, required OrderMode mode}) {
  final base = subtotalEgp / egpPerPoint;
  final scaled = mode == OrderMode.dineIn ? base * dineInMultiplier : base;
  return roundHalfUp(scaled);
}

/// Canonical preview — delegates to loyalty_rules.earnedFor with fallback config.
/// Prefer this over pointsPreviewFor (ARCH-06).
int pointsPreviewCanonical({
  required int subtotalEgp,
  required bool dineIn,
  double pointsPer10 = 1.0,
  double dineInMulti = 1.1,
  bool doubleWindow = false,
}) {
  final base = subtotalEgp * pointsPer10 / 10;
  final scaled = base * (dineIn ? dineInMulti : 1) * (doubleWindow ? 2 : 1);
  return roundHalfUp(scaled);
}

// ---------------------------------------------------------------------------
// Pickup slots — Cairo wall clock computed locally, stored as UTC (§11.30)
// ---------------------------------------------------------------------------

class PickupSlotOption {
  const PickupSlotOption({required this.startUtc, required this.label});

  /// UTC instant sent as `timestamptz`.
  final DateTime startUtc;

  /// Africa/Cairo wall clock `HH:mm` — Western digits (§11.11).
  final String label;
}

String _two(int value) => value.toString().padLeft(2, '0');

DateTime _lastWeekdayOfMonthUtc(int year, int month, int weekday) {
  var day = DateTime.utc(year, month + 1, 0); // last day of month
  while (day.weekday != weekday) {
    day = day.subtract(const Duration(days: 1));
  }
  return DateTime.utc(day.year, day.month, day.day);
}

/// Egypt DST (2023+): last Friday of April 00:00 → midnight ending the last
/// Thursday of October, so the Friday after it is already winter time.
bool _cairoIsDst(DateTime utcDateNoon) {
  final year = utcDateNoon.year;
  final dstStart =
      _lastWeekdayOfMonthUtc(year, DateTime.april, DateTime.friday);
  final dstEndExclusive =
      _lastWeekdayOfMonthUtc(year, DateTime.october, DateTime.thursday)
          .add(const Duration(days: 1));
  return !utcDateNoon.isBefore(dstStart) && utcDateNoon.isBefore(dstEndExclusive);
}

Duration cairoUtcOffset(DateTime utcInstant) {
  final probe = utcInstant.add(const Duration(hours: 2)); // standard offset
  final dateNoon = DateTime.utc(
    probe.year,
    probe.month,
    probe.day,
    12,
  );
  return _cairoIsDst(dateNoon)
      ? const Duration(hours: 3)
      : const Duration(hours: 2);
}

/// Cairo `dd/MM HH:mm` for `risk_evaluated_at` display — Western digits §11.11,
/// UTC storage `timestamptz` → Cairo wall via [cairoUtcOffset] (ADR-0009).
/// Mirrors `formatLookupWhenUtc` but lives beside [cairoUtcOffset].
String formatRiskEvaluatedAt(DateTime utcInstant) {
  assert(utcInstant.isUtc, 'pass DateTime.now().toUtc() — isUtc must be true');
  final cairo = utcInstant.add(cairoUtcOffset(utcInstant));
  return '${_two(cairo.day)}/${_two(cairo.month)} ${_two(cairo.hour)}:${_two(cairo.minute)}';
}

/// [nowUtc] must be a UTC instant. Slots are the next [count] half-hour
/// boundaries on the Cairo wall clock (the first one may be exactly "now"
/// when called on a whole half hour); labels are Cairo `HH:mm`, instants UTC.
List<PickupSlotOption> upcomingPickupSlots(DateTime nowUtc, {int count = 3}) {
  assert(count > 0 && nowUtc.isUtc, 'pass DateTime.now().toUtc()');
  final nowOffset = cairoUtcOffset(nowUtc);
  final cairoNow = nowUtc.add(nowOffset); // UTC-flagged naive Cairo timeline
  var minutes = cairoNow.hour * 60 + cairoNow.minute;
  final subMinute = cairoNow.second != 0 ||
      cairoNow.millisecond != 0 ||
      cairoNow.microsecond != 0;
  if (minutes % 30 != 0 || subMinute) {
    minutes = (minutes ~/ 30 + 1) * 30;
  }
  final dayStart = DateTime.utc(cairoNow.year, cairoNow.month, cairoNow.day);
  return List.generate(count, (index) {
    final naive = dayStart.add(Duration(minutes: minutes + 30 * index));
    final probe = naive.subtract(const Duration(hours: 2));
    final slotOffset = cairoUtcOffset(probe);
    return PickupSlotOption(
      startUtc: naive.subtract(slotOffset),
      label: '${_two(naive.hour)}:${_two(naive.minute)}',
    );
  });
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum AddressLabel { home, work, other }

class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.addressText,
    this.latitude,
    this.longitude,
  });

  final String id;
  final AddressLabel label;
  final String addressText;
  final double? latitude;
  final double? longitude;
}

class SavedAddressInput {
  const SavedAddressInput({
    required this.googleUserId,
    required this.label,
    required this.addressText,
    this.latitude,
    this.longitude,
  });

  final String googleUserId;
  final AddressLabel label;
  final String addressText;
  final double? latitude;
  final double? longitude;
}

/// One cart line flattened for the `orders.items` jsonb snapshot:
/// `{id, name_ar, qty, unit_total, config:{size, sugar, addons[], note}}`.
class OrderItemPayload {
  const OrderItemPayload({
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

  static String _sanitizeNote(String note) =>
      note.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  Map<String, dynamic> toJson() {
    final sanitizedNote = config.note == null
        ? null
        : _sanitizeNote(config.note!);
    return {
      'id': id,
      'name_ar': nameAr,
      'qty': qty,
      'unit_total': unitTotalEgp,
      'config': {
        'size': config.sizeIndex,
        'sugar': config.sugarIndex,
        'addons': config.addons.toList()..sort(),
        if (sanitizedNote != null && sanitizedNote.isNotEmpty)
          'note': sanitizedNote,
      },
    };
  }
}

/// Row handed to [OrdersRepo.placeOrder]; phone resolves server-side from
/// `customers.google_user_id` when omitted.
/// RISK-03: [deviceId] is the stable `risk.device_id` (UUID v4) per install —
/// untrusted signal, nullable, never required. Documented choice: stored in
/// `orders.device_id` (new column in 0021_device_and_address.sql).
/// RISK-04: [idempotencyKey] is a per-submit UUID v4 for duplicate suppression
/// (30s debounce in checkout_screen.dart + server unique index on (phone, idempotency_key)).
/// RISK-07: client never sends `risk_*`, `phone_verified`, `successful_orders`,
/// `failed_deliveries`, etc. — server derives from `customer_risk_profiles` +
/// `addresses` + `customer_devices`; SupabaseOrdersRepo strips these before insert.
class NewOrder {
  const NewOrder({
    required this.mode,
    required this.googleUserId,
    required this.items,
    required this.subtotalEgp,
    required this.deliveryFeeEgp,
    required this.totalEgp,
    required this.pointsPreview,
    this.phone,
    this.tableArea,
    this.pickupSlotUtc,
    this.addressId,
    this.notes,
    this.deviceId,
    this.idempotencyKey,
  });

  final OrderMode mode;
  final String googleUserId;
  final List<OrderItemPayload> items;
  final int subtotalEgp;
  final int deliveryFeeEgp;
  final int totalEgp;
  final int pointsPreview;
  final String? phone;
  final String? tableArea;
  final DateTime? pickupSlotUtc;
  final String? addressId;
  final String? notes;
  final String? deviceId;
  final String? idempotencyKey;
}

class PlacedOrder {
  const PlacedOrder({
    required this.id,
    required this.displayNumber,
    this.riskAction,
    this.riskScore,
    this.riskLevel,
    this.riskReasons,
  });

  final String id;

  /// From `order_display_seq` via the DB trigger (#1000+).
  final int displayNumber;

  /// Server-computed risk gate result (RISK-04). Null for pre-risk orders.
  /// Checkout respects this without trusting client (server-authoritative).
  final String? riskAction;
  final int? riskScore;
  final String? riskLevel;
  final List<String>? riskReasons;

  /// Convenience typed getters
  RiskAction? get riskActionTyped =>
      riskAction == null ? null : RiskActionX.tryFromWire(riskAction!);
  RiskLevel? get riskLevelTyped =>
      riskLevel == null ? null : RiskLevelX.tryFromWire(riskLevel!);

  bool get needsVerification => riskAction == 'needs_verification';
  bool get isRejected => riskAction == 'rejected';
}

/// Snapshot carried to `/confirmation` through the router `extra`.
class ConfirmationArgs {
  const ConfirmationArgs({
    required this.displayNumber,
    required this.mode,
    required this.items,
    required this.subtotalEgp,
    required this.deliveryFeeEgp,
    required this.totalEgp,
    required this.pointsPreview,
  });

  final int displayNumber;
  final OrderMode mode;
  final List<OrderItemPayload> items;
  final int subtotalEgp;
  final int deliveryFeeEgp;
  final int totalEgp;
  final int pointsPreview;
}

// ---------------------------------------------------------------------------
// Checkout draft — shared between mode selection, cart notes and checkout
// ---------------------------------------------------------------------------

/// استلام timing: either الآن (null slot) or an explicit half-hour slot.
class PickupTiming {
  const PickupTiming.now()
      : isNow = true,
        slotUtc = null;
  const PickupTiming.slot(DateTime this.slotUtc) : isNow = false;

  final bool isNow;
  final DateTime? slotUtc;
}

class CheckoutDraft {
  const CheckoutDraft({
    this.mode,
    this.tableArea,
    this.pickupTiming = const PickupTiming.now(),
    this.addressId,
    this.notes = '',
  });

  final OrderMode? mode;

  /// Composed dine-in detail, e.g. `طاولة 12` or `داخل` / `تراس`.
  final String? tableArea;
  final PickupTiming? pickupTiming;
  final String? addressId;
  final String notes;

  bool get canSubmit => switch (mode) {
        null => false,
        OrderMode.dineIn => tableArea != null && tableArea!.trim().isNotEmpty,
        OrderMode.pickup => pickupTiming != null,
        OrderMode.delivery => addressId != null && addressId!.trim().isNotEmpty,
      };

  static const _sentinel = Object();

  CheckoutDraft copyWith({
    Object? mode = _sentinel,
    Object? tableArea = _sentinel,
    Object? pickupTiming = _sentinel,
    Object? addressId = _sentinel,
    Object? notes = _sentinel,
  }) {
    return CheckoutDraft(
      mode: mode == _sentinel ? this.mode : mode as OrderMode?,
      tableArea: tableArea == _sentinel ? this.tableArea : tableArea as String?,
      pickupTiming:
          pickupTiming == _sentinel ? this.pickupTiming : pickupTiming as PickupTiming?,
      addressId: addressId == _sentinel ? this.addressId : addressId as String?,
      notes: notes == _sentinel ? this.notes : notes as String,
    );
  }
}

class CheckoutDraftController extends Notifier<CheckoutDraft> {
  @override
  CheckoutDraft build() => const CheckoutDraft();

  void setMode(OrderMode mode) {
    state = CheckoutDraft(
      mode: mode,
      tableArea: state.mode == mode ? state.tableArea : null,
      pickupTiming: const PickupTiming.now(),
      notes: state.notes,
    );
  }

  void setTableArea(String? value) =>
      state = state.copyWith(tableArea: (value ?? '').trim());

  void setPickupTiming(PickupTiming? timing) =>
      state = state.copyWith(pickupTiming: timing);

  void setAddressId(String? id) => state = state.copyWith(addressId: id);

  void setNotes(String value) =>
      state = state.copyWith(notes: value.trim().isEmpty ? '' : value);

  void reset() => state = const CheckoutDraft();
}

final checkoutDraftProvider =
    NotifierProvider<CheckoutDraftController, CheckoutDraft>(
  CheckoutDraftController.new,
);

// ---------------------------------------------------------------------------
// Repository seam + Supabase implementation
// ---------------------------------------------------------------------------

abstract class OrdersRepo {
  /// Admin-editable flat fee (app_config `delivery_fee`); falls back to
  /// [defaultDeliveryFeeEgp] when the row is missing or unreachable.
  Future<int> fetchDeliveryFee();

  Future<List<SavedAddress>> fetchAddresses(String googleUserId);

  Future<SavedAddress> saveAddress(SavedAddressInput input);

  /// Inserts with `status='new'`; RLS requires the caller's own
  /// `google_user_id`. Returns the DB-assigned display number (#1000+).
  Future<PlacedOrder> placeOrder(NewOrder order);

  /// Preview seam — deep RiskEngine behind one call, no persistence.
  /// Hides RiskContext assembly; server remains authoritative for writes.
  Future<RiskResult> previewRisk(NewOrder draft);
}

List<String>? _parseRiskReasons(Object? v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return null;
}

/// Canonical intake key for the deep Order Intake module — single
/// content-addressed idempotency key (phone + items + address). Replaces the
/// old `Uuid.v4` nonce + brittle `md5(items::text)` dual track.
String _intakeKeyFor(NewOrder order, String? phone) {
  return intake.orderIntakeKeyFromJson(
    phone: phone,
    googleUserId: order.googleUserId,
    itemsJson: [for (final i in order.items) i.toJson()],
    addressId: order.addressId,
  );
}

/// Adapter that owns RiskContext assembly — Locality concentrated here, checkout never builds RiskContext.
/// Pure for tests (zeros), plus async honest path that mirrors server pipeline 0030.
class RiskPreviewAdapter {
  const RiskPreviewAdapter(this.engine);
  final RiskEngine engine;

  RiskResult previewFor(
    NewOrder draft, {
    RiskProfile? profile,
    int deviceCustomerCount = 0,
    int addressCustomerCount = 0,
    int addressFailedCount = 0,
    bool isNewDeviceOverride = false,
    bool useNewDeviceOverride = false,
    bool isRapidOrders = false,
  }) {
    final isNewDevice = useNewDeviceOverride
        ? isNewDeviceOverride
        : (draft.deviceId != null && draft.deviceId!.trim().isNotEmpty);
    final ctx = RiskContext(
      subtotalEgp: draft.subtotalEgp,
      isNewCustomer: profile == null ? true : profile.totalOrders == 0,
      previousFailedDeliveries: profile?.failedDeliveries ?? 0,
      previousRejectedOrders: profile?.rejectedOrders ?? 0,
      cancellationsCount: profile?.cancelledOrders ?? 0,
      successfulOrders: profile?.successfulOrders ?? 0,
      isVerifiedPhone: profile?.phoneVerified ?? false,
      isLargeOrder: draft.subtotalEgp >= engine.config.largeOrderThreshold,
      isNewDevice: isNewDevice,
      deviceCustomerCount: deviceCustomerCount,
      addressCustomerCount: addressCustomerCount,
      addressFailedCount: addressFailedCount,
      isRapidOrders: isRapidOrders,
    );
    return engine.evaluate(ctx);
  }
}

class SupabaseOrdersRepo implements OrdersRepo {
  SupabaseOrdersRepo(this._client, {RiskEngine? engine}) : _engine = engine ?? const RiskEngine();

  final SupabaseClient _client;
  final RiskEngine _engine;

  @override
  Future<int> fetchDeliveryFee() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'delivery_fee')
          .maybeSingle();
      final value = row?['value'];
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    } catch (_) {
      // Offline/config hiccup — standard policy: fall back to the constant.
    }
    return defaultDeliveryFeeEgp;
  }

  Future<String?> _phoneOf(String googleUserId) async =>
      resolvePhone(_client, googleUserId);

  @override
  Future<List<SavedAddress>> fetchAddresses(String googleUserId) async {
    final rows = await _client //
        .from('addresses')
        .select(
          'id, label, address_text, latitude, longitude, customers!inner(google_user_id)',
        )
        .eq('customers.google_user_id', googleUserId)
        .order('created_at', ascending: true);
    double? parseDouble(Object? v) {
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    AddressLabel parseLabel(Object? raw) {
      if (raw is String) {
        for (final v in AddressLabel.values) {
          if (v.name == raw) return v;
        }
      }
      return AddressLabel.other;
    }

    return [
      for (final row in List<Map<String, dynamic>>.from(rows as List))
        SavedAddress(
          id: row['id'] as String,
          label: parseLabel(row['label']),
          addressText: row['address_text'] as String,
          latitude: parseDouble(row['latitude']),
          longitude: parseDouble(row['longitude']),
        ),
    ];
  }

  @override
  Future<SavedAddress> saveAddress(SavedAddressInput input) async {
    final phone = await _phoneOf(input.googleUserId);
    if (phone == null) {
      throw StateError('customer-not-found-for-address');
    }
    final row = await _client //
        .from('addresses')
        .insert({
          'phone': phone,
          'label': input.label.name,
          'address_text': input.addressText,
          if (input.latitude case final v?) 'latitude': v,
          if (input.longitude case final v?) 'longitude': v,
        })
        .select('id, label, address_text, latitude, longitude')
        .single();
    double? parseDouble(Object? v) {
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    AddressLabel parseLabel(Object? raw) {
      if (raw is String) {
        for (final v in AddressLabel.values) {
          if (v.name == raw) return v;
        }
      }
      return AddressLabel.other;
    }

    return SavedAddress(
      id: row['id'] as String,
      label: parseLabel(row['label']),
      addressText: row['address_text'] as String,
      latitude: parseDouble(row['latitude']),
      longitude: parseDouble(row['longitude']),
    );
  }

  @override
  Future<RiskResult> previewRisk(NewOrder draft) async {
    RiskProfile? profile;
    String? phone;
    try {
      phone = draft.phone ?? await _phoneOf(draft.googleUserId);
      if (phone != null) {
        final row = await _client.from('customer_risk_profiles').select().eq('phone', phone).maybeSingle();
        if (row != null) {
          profile = RiskProfile.fromRow(Map<String, dynamic>.from(row as Map));
        }
      }
    } catch (_) {
      // Fallback — preview as new Customer
    }

    // Honest preview: mirror server pipeline 0030 counts (best-effort, fallback 0/false).
    var deviceCustomerCount = 0;
    var addressCustomerCount = 0;
    var addressFailedCount = 0;
    var isRapidOrders = false;
    var isNewDevice = false;
    var useNewDeviceOverride = false;

    final deviceId = draft.deviceId?.trim();
    if (deviceId != null && deviceId.isNotEmpty) {
      try {
        // distinct phones using this device_id
        final rows = await _client.from('customer_devices').select('phone').eq('device_id', deviceId);
        final distinct = {for (final r in (rows as List)) (r as Map)['phone'] as String?}.whereType<String>().length;
        if (phone != null && phone.isNotEmpty) {
          final exists = await _client.from('customer_devices').select('phone').eq('phone', phone).eq('device_id', deviceId).maybeSingle();
          isNewDevice = exists == null;
          deviceCustomerCount = isNewDevice ? distinct + 1 : distinct;
        } else {
          isNewDevice = true;
          deviceCustomerCount = distinct + 1;
        }
        useNewDeviceOverride = true;
      } catch (_) {
        // keep defaults
      }
    }

    final addressId = draft.addressId?.trim();
    if (addressId != null && addressId.isNotEmpty) {
      try {
        final rows = await _client.from('orders').select('phone').eq('address_id', addressId);
        final distinct = {for (final r in (rows as List)) (r as Map)['phone'] as String?}.whereType<String>().length;
        if (phone != null && phone.isNotEmpty) {
          final hasPhone = await _client.from('orders').select('phone').eq('address_id', addressId).eq('phone', phone).maybeSingle();
          addressCustomerCount = hasPhone != null ? distinct : distinct + 1;
        } else {
          addressCustomerCount = distinct;
        }
        final failedRows = await _client.from('orders').select('id').eq('address_id', addressId).eq('status', 'cancelled');
        addressFailedCount = (failedRows as List).length;
      } catch (_) {}
    }

    if (phone != null && phone.isNotEmpty) {
      try {
        final window = _engine.config.rapidOrdersWindowMinutes;
        final threshold = _engine.config.rapidOrdersCount;
        if (window > 0 && threshold > 0) {
          final since = DateTime.now().toUtc().subtract(Duration(minutes: window)).toIso8601String();
          final recent = await _client.from('orders').select('id').eq('phone', phone).gte('created_at', since);
          final count = (recent as List).length;
          isRapidOrders = (count + 1) >= threshold;
        }
      } catch (_) {}
    }

    return RiskPreviewAdapter(_engine).previewFor(
      draft,
      profile: profile,
      deviceCustomerCount: deviceCustomerCount,
      addressCustomerCount: addressCustomerCount,
      addressFailedCount: addressFailedCount,
      isNewDeviceOverride: isNewDevice,
      useNewDeviceOverride: useNewDeviceOverride,
      isRapidOrders: isRapidOrders,
    );
  }

  @override
  Future<PlacedOrder> placeOrder(NewOrder order) async {
    final phone = order.phone ?? await _phoneOf(order.googleUserId);
    // Deep Order Intake: single content-addressed key (phone + items + address)
    // stable across retries — no Uuid.v4 nonce. Mirrors SQL
    // compute_order_intake_hash(phone, items, address_id). Recovery is single
    // lookup by that key (no triple fallback, no jsonb::text divergence).
    // When caller supplies an explicit key (tests), respect it.
    final contentKey = order.idempotencyKey?.trim().isNotEmpty == true
        ? order.idempotencyKey!.trim()
        : _intakeKeyFor(order, phone);

    try {
      final row = await _client //
          .from('orders')
          .insert({
            'google_user_id': order.googleUserId,
            'phone': ?phone,
            'mode': order.mode.wireName,
            'status': 'new',
            'items': [for (final item in order.items) item.toJson()],
            'subtotal': order.subtotalEgp,
            'delivery_fee': order.deliveryFeeEgp,
            'total': order.totalEgp,
            if (order.tableArea != null && order.tableArea!.trim().isNotEmpty)
              'table_area': order.tableArea,
            if (order.pickupSlotUtc != null)
              'pickup_slot': order.pickupSlotUtc!.toIso8601String(),
            if (order.addressId != null && order.addressId!.trim().isNotEmpty)
              'address_id': order.addressId,
            if (order.notes != null && order.notes!.trim().isNotEmpty)
              'notes': order.notes,
            'points_preview': order.pointsPreview,
            if (order.deviceId != null && order.deviceId!.trim().isNotEmpty)
              'device_id': order.deviceId!.trim(),
            'idempotency_key': contentKey,
          })
          .select('id, display_number, risk_action, risk_score, risk_level, risk_reasons')
          .single();
      return PlacedOrder(
        id: row['id'] as String,
        displayNumber: (row['display_number'] as num).toInt(),
        riskAction: row['risk_action'] as String?,
        riskScore: (row['risk_score'] as num?)?.toInt(),
        riskLevel: row['risk_level'] as String?,
        riskReasons: _parseRiskReasons(row['risk_reasons']),
      );
    } on PostgrestException catch (e) {
      final combinedLower = '${e.message} ${e.hint ?? ''}'.toLowerCase();
      // Rate-limit P0001 (too_many_orders / rapid_orders) must not be
      // swallowed — rethrow so UI can show throttling banner.
      final isRateLimited = e.code == 'P0001' &&
          (combinedLower.contains('rate limited') ||
              (e.hint ?? '').toLowerCase().contains('too_many_orders') ||
              (e.hint ?? '').toLowerCase().contains('rapid_orders'));
      if (isRateLimited) rethrow;

      // Single recovery: 23505 unique violation or P0001 duplicate window
      // both resolve by fetching the existing order with the same content key.
      if (e.code == '23505' || (e.code == 'P0001' && combinedLower.contains('duplicate'))) {
        // Prefer hint-parsed id if pipeline raised duplicate with hint.
        final searchText = '${e.hint ?? ''} ${e.message}';
        final idMatch = RegExp(
          r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
          caseSensitive: false,
        ).firstMatch(searchText);
        if (idMatch != null) {
          final existingId = idMatch.group(0)!;
          try {
            final existing = await _client
                .from('orders')
                .select('id, display_number, risk_action, risk_score, risk_level, risk_reasons')
                .eq('id', existingId)
                .single();
            return PlacedOrder(
              id: existing['id'] as String,
              displayNumber: (existing['display_number'] as num).toInt(),
              riskAction: existing['risk_action'] as String?,
              riskScore: (existing['risk_score'] as num?)?.toInt(),
              riskLevel: existing['risk_level'] as String?,
              riskReasons: _parseRiskReasons(existing['risk_reasons']),
            );
          } catch (_) {
            // fall through to content-key lookup
          }
        }
        try {
          final existing = await _client
              .from('orders')
              .select('id, display_number, risk_action, risk_score, risk_level, risk_reasons')
              .eq(phone != null ? 'phone' : 'google_user_id', phone ?? order.googleUserId)
              .eq('idempotency_key', contentKey)
              .order('created_at', ascending: false)
              .limit(1)
              .single();
          return PlacedOrder(
            id: existing['id'] as String,
            displayNumber: (existing['display_number'] as num).toInt(),
            riskAction: existing['risk_action'] as String?,
            riskScore: (existing['risk_score'] as num?)?.toInt(),
            riskLevel: existing['risk_level'] as String?,
            riskReasons: _parseRiskReasons(existing['risk_reasons']),
          );
        } catch (_) {
          rethrow;
        }
      }
      rethrow;
    }
  }
}

final ordersRepoProvider = Provider<OrdersRepo>(
  (ref) {
    final engine = ref.watch(riskEngineProvider).asData?.value ?? const RiskEngine();
    return SupabaseOrdersRepo(supabase, engine: engine);
  },
);

/// Admin-configured delivery fee; `valueOrNull` keeps the constant as the
/// graceful fallback while loading/offline.
final deliveryFeeProvider = FutureProvider<int>(
  (ref) => ref.watch(ordersRepoProvider).fetchDeliveryFee(),
);
