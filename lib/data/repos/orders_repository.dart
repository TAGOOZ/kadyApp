// Orders slice data layer (issue #003): Supabase-backed orders/addresses
// access plus the pure checkout math — points preview (round half-up with
// dine-in ×1.1), totals with flat delivery fee, and Africa/Cairo half-hour
// pickup slots emitted as UTC instants (ADR-0009). All supabase calls sit
// behind the OrdersRepo seam so tests never hit the network.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../models/menu_models.dart';

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

const defaultDeliveryFeeEgp = 15; // §11.7 — flat citywide, admin-editable.
const dineInMultiplier = 1.1; // §4 — dine-in bonus multiplier.
const egpPerPoint = 10; // §4 — 1 pt / 10 EGP.

/// Round half-up applied to the FINAL earned value, after multipliers (§4):
/// 95 EGP → 9.5 pts → 10 pts; dine-in 90 EGP → 9 × 1.1 = 9.9 → 10 pts.
int roundHalfUp(double value) {
  final floored = value.floor();
  final fraction = value - floored;
  return floored + (fraction >= 0.5 ? 1 : 0);
}

/// Delivery pays the flat fee; صالة/استلام pay nothing (fee row hidden).
int deliveryFeeFor(OrderMode mode, {int configuredFeeEgp = defaultDeliveryFeeEgp}) {
  return mode == OrderMode.delivery ? configuredFeeEgp : 0;
}

int totalOf({required int subtotalEgp, required int deliveryFeeEgp}) {
  return subtotalEgp + deliveryFeeEgp;
}

/// Real earn preview shown before submitting (placeholder box until #007).
int pointsPreviewFor({required int subtotalEgp, required OrderMode mode}) {
  final base = subtotalEgp / egpPerPoint;
  final scaled = mode == OrderMode.dineIn ? base * dineInMultiplier : base;
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
  });

  final String id;
  final AddressLabel label;
  final String addressText;
}

class SavedAddressInput {
  const SavedAddressInput({
    required this.googleUserId,
    required this.label,
    required this.addressText,
  });

  final String googleUserId;
  final AddressLabel label;
  final String addressText;
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

/// Row handed to [OrdersRepo.placeOrder]; phone resolves server-side from
/// `customers.google_user_id` when omitted.
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
}

class PlacedOrder {
  const PlacedOrder({required this.id, required this.displayNumber});

  final String id;

  /// From `order_display_seq` via the DB trigger (#1000+).
  final int displayNumber;
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

  CheckoutDraft copyWith({
    OrderMode? mode,
    String? tableArea,
    PickupTiming? pickupTiming,
    String? addressId,
    String? notes,
  }) {
    return CheckoutDraft(
      mode: mode ?? this.mode,
      tableArea: tableArea ?? this.tableArea,
      pickupTiming: pickupTiming ?? this.pickupTiming,
      addressId: addressId ?? this.addressId,
      notes: notes ?? this.notes,
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

  void setPickupTiming(PickupTiming timing) =>
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
}

class SupabaseOrdersRepo implements OrdersRepo {
  SupabaseOrdersRepo(this._client);

  final SupabaseClient _client;

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

  Future<String?> _phoneOf(String googleUserId) async {
    final row = await _client
        .from('customers')
        .select('phone')
        .eq('google_user_id', googleUserId)
        .maybeSingle();
    return row?['phone'] as String?;
  }

  @override
  Future<List<SavedAddress>> fetchAddresses(String googleUserId) async {
    final rows = await _client //
        .from('addresses')
        .select('id, label, address_text, customers!inner(google_user_id)')
        .eq('customers.google_user_id', googleUserId)
        .order('created_at', ascending: true);
    return [
      for (final row in List<Map<String, dynamic>>.from(rows as List))
        SavedAddress(
          id: row['id'] as String,
          label: AddressLabel.values.byName(row['label'] as String),
          addressText: row['address_text'] as String,
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
        })
        .select('id, label, address_text')
        .single();
    return SavedAddress(
      id: row['id'] as String,
      label: AddressLabel.values.byName(row['label'] as String),
      addressText: row['address_text'] as String,
    );
  }

  @override
  Future<PlacedOrder> placeOrder(NewOrder order) async {
    final phone = order.phone ?? await _phoneOf(order.googleUserId);
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
        })
        .select('id, display_number')
        .single();
    return PlacedOrder(
      id: row['id'] as String,
      displayNumber: (row['display_number'] as num).toInt(),
    );
  }
}

final ordersRepoProvider = Provider<OrdersRepo>(
  (ref) => SupabaseOrdersRepo(supabase),
);

/// Admin-configured delivery fee; `valueOrNull` keeps the constant as the
/// graceful fallback while loading/offline.
final deliveryFeeProvider = FutureProvider<int>(
  (ref) => ref.watch(ordersRepoProvider).fetchDeliveryFee(),
);
