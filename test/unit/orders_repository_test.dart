// Checkout math unit tests (issue #003): points preview rounding (§4),
// delivery-fee totals (§11.7), mode validation and Cairo pickup slots
// emitted as UTC instants (ADR-0009). No network, no Supabase.
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/orders_repository.dart';

void main() {
  group('pointsPreviewFor — round half-up on the final value', () {
    test('95 EGP → 9.5 pts → 10 pts (spec example)', () {
      // 95 / 10 = 9.5 exactly; round half-up must go UP, never banker's.
      expect(pointsPreviewFor(subtotalEgp: 95, mode: OrderMode.pickup), 10);
    });

    test('90 EGP dine-in → 9 × 1.1 = 9.9 → 10 pts (spec example)', () {
      expect(
        pointsPreviewFor(subtotalEgp: 90, mode: OrderMode.dineIn),
        10,
      );
    });

    test('100 EGP dine-in → 10 × 1.1 = 11 pts', () {
      expect(
        pointsPreviewFor(subtotalEgp: 100, mode: OrderMode.dineIn),
        11,
      );
    });

    test('200 EGP delivery → 20 pts (no dine-in multiplier)', () {
      expect(
        pointsPreviewFor(subtotalEgp: 200, mode: OrderMode.delivery),
        20,
      );
    });

    test('45 EGP pickup → 4.5 pts → 5 pts', () {
      expect(pointsPreviewFor(subtotalEgp: 45, mode: OrderMode.pickup), 5);
    });
  });

  group('deliveryFeeFor + totalOf — flat fee only for delivery', () {
    test('delivery uses the configured fee (default 15)', () {
      expect(deliveryFeeFor(OrderMode.delivery), 15);
      expect(
        deliveryFeeFor(OrderMode.delivery, configuredFeeEgp: 20),
        20,
      );
    });

    test('pickup/dine-in pay nothing even when a fee is configured', () {
      expect(
        deliveryFeeFor(OrderMode.pickup, configuredFeeEgp: 20),
        0,
      );
      expect(
        deliveryFeeFor(OrderMode.dineIn, configuredFeeEgp: 20),
        0,
      );
    });

    test('totals add fee for delivery, not for other modes', () {
      expect(totalOf(subtotalEgp: 100, deliveryFeeEgp: 15), 115);
      expect(totalOf(subtotalEgp: 100, deliveryFeeEgp: 0), 100);
    });
  });

  group('CheckoutDraft.canSubmit — per-mode required fields', () {
    test('delivery is blocked without an address', () {
      const draft = CheckoutDraft(mode: OrderMode.delivery);
      expect(draft.canSubmit, isFalse);

      final withAddress =
          draft.copyWith(addressId: 'a1b2c3');
      expect(withAddress.canSubmit, isTrue);
    });

    test('dine-in requires a table number or an area', () {
      const empty = CheckoutDraft(mode: OrderMode.dineIn);
      expect(empty.canSubmit, isFalse);

      expect(
        empty.copyWith(tableArea: 'طاولة 12').canSubmit,
        isTrue,
      );
      expect(empty.copyWith(tableArea: 'تراس').canSubmit, isTrue);
      expect(empty.copyWith(tableArea: '   ').canSubmit, isFalse);
    });

    test('pickup defaults to الآن so it is submittable immediately', () {
      const draft = CheckoutDraft(mode: OrderMode.pickup);
      expect(draft.pickupTiming?.isNow ?? true, isTrue);
      expect(draft.canSubmit, isTrue);

      final slotted =
          draft.copyWith(pickupTiming: PickupTiming.slot(_utc(14, 30)));
      expect(slotted.pickupTiming?.isNow, isFalse);
      expect(slotedSlotUtc(slotted), _utc(14, 30));
    });
  });

  group('upcomingPickupSlots — Cairo wall clock → UTC instants', () {
    test('summer (+3): 10:07:30Z → 13:30/14:00/14:30 Cairo', () {
      final now = DateTime.utc(2026, 8, 22, 10, 7, 30);
      final slots = upcomingPickupSlots(now);

      expect(slots, hasLength(3));
      expect(
        slots.map((s) => s.startUtc).toList(),
        [
          DateTime.utc(2026, 8, 22, 10, 30),
          DateTime.utc(2026, 8, 22, 11, 0),
          DateTime.utc(2026, 8, 22, 11, 30),
        ],
      );
      expect(slots.map((s) => s.label).toList(),
          ['13:30', '14:00', '14:30']);
    });

    test('winter (+2): 09:20:00Z → 11:30/12:00/12:30 Cairo', () {
      final now = DateTime.utc(2026, 1, 15, 9, 20);
      final slots = upcomingPickupSlots(now);

      expect(
        slots.map((s) => s.startUtc).toList(),
        [
          DateTime.utc(2026, 1, 15, 9, 30),
          DateTime.utc(2026, 1, 15, 10, 0),
          DateTime.utc(2026, 1, 15, 10, 30),
        ],
      );
      expect(slots.map((s) => s.label).toList(),
          ['11:30', '12:00', '12:30']);
    });

    test('exact half hour stays as the first slot; sub-minute rolls over',
        () {
      expect(
        upcomingPickupSlots(DateTime.utc(2026, 8, 22, 10, 30))
            .first
            .startUtc,
        DateTime.utc(2026, 8, 22, 10, 30),
      );
      expect(
        upcomingPickupSlots(DateTime.utc(2026, 8, 22, 10, 30, 0, 500))
            .first
            .startUtc,
        DateTime.utc(2026, 8, 22, 11, 0),
      );
    });

    test('Cairo midnight rollover keeps UTC instants on the previous day',
        () {
      // 21:55Z summer = 00:55 Cairo next day → first slot 01:00 Cairo.
      final slots = upcomingPickupSlots(DateTime.utc(2026, 8, 22, 21, 55));
      expect(slots.first.label, '01:00');
      expect(slots.first.startUtc, DateTime.utc(2026, 8, 22, 22, 0));
    });

    test('DST edges follow Egypt rules (2026: Apr 24 → Oct 29)', () {
      // Winter before last Friday of April.
      expect(
        cairoUtcOffset(DateTime.utc(2026, 4, 23, 12)),
        const Duration(hours: 2),
      );
      // Summer on the switch-on day itself.
      expect(
        cairoUtcOffset(DateTime.utc(2026, 4, 24, 21, 30)),
        const Duration(hours: 3),
      );
      // Still +3 late evening of the last Thursday of October…
      expect(
        cairoUtcOffset(DateTime.utc(2026, 10, 29, 21)),
        const Duration(hours: 3),
      );
      // …but +2 from Friday 00:00 Cairo (= Thu 22:00 UTC).
      expect(
        cairoUtcOffset(DateTime.utc(2026, 10, 29, 22)),
        const Duration(hours: 2),
      );
    });
  });

  group('OrderItemPayload.toJson — orders.items jsonb shape', () {
    test('matches {id, name_ar, qty, unit_total, config{size,sugar,addons}}',
        () {
      const payload = OrderItemPayload(
        id: 'latte',
        nameAr: 'لاتيه',
        qty: 2,
        unitTotalEgp: 65,
        config: ItemConfig(
          sizeIndex: 1,
          sugarIndex: 2,
          addons: {'espresso_shot'},
        ),
      );

      final json = payload.toJson();
      expect(json['id'], 'latte');
      expect(json['name_ar'], 'لاتيه');
      expect(json['qty'], 2);
      expect(json['unit_total'], 65);
      final config = json['config'] as Map<String, dynamic>;
      expect(config['size'], 1);
      expect(config['sugar'], 2);
      expect(config['addons'], ['espresso_shot']);
      expect(config.containsKey('note'), isFalse);
    });

    test('note included only when non-blank', () {
      const withNote = OrderItemPayload(
        id: 'x',
        nameAr: 'س',
        qty: 1,
        unitTotalEgp: 10,
        config: ItemConfig(note: 'بدون سكر'),
      );
      expect(withNote.toJson()['config']['note'], 'بدون سكر');

      const blankNote = OrderItemPayload(
        id: 'x',
        nameAr: 'س',
        qty: 1,
        unitTotalEgp: 10,
        config: ItemConfig(note: '   '),
      );
      expect(blankNote.toJson()['config'].containsKey('note'), isFalse);
    });
  });
}

DateTime _utc(int hour, int minute) =>
    DateTime.utc(2026, 8, 22, hour, minute);

DateTime slotedSlotUtc(CheckoutDraft draft) => draft.pickupTiming!.slotUtc!;
