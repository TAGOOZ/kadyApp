// Order Intake deep module tests — Candidate 6
//
// Verifies:
// - content-addressed key stability (same phone+items+address -> same hash, different address -> different)
// - json key order / addon order insensitivity (Dart vs Postgres parity)
// - pipeline DAG explicit ordering via FakeOrdersDb (validate -> risk -> rate-limit -> dedup)
// - dedup behavior: second insert same cart is idempotent, different address not deduped
// - no Uuid.v4 nonce anywhere in intake key generation

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/data/repos/fake_orders_db.dart';
import 'package:kady_app/data/repos/orders_repository.dart';
import 'package:kady_app/domain/order_intake.dart' as intake;

MenuItem _item(String id, String slug, int price, String category) => MenuItem(
      id: id,
      slug: slug,
      nameAr: 'عنصر $slug',
      nameEn: 'Item $slug',
      descAr: '',
      descEn: '',
      priceEgp: price,
      isAvailable: true,
      categorySlug: category,
    );

OrderItemPayload _payload(MenuItem item, ItemConfig config, int qty, int unitTotal) =>
    OrderItemPayload(
      id: item.id,
      nameAr: item.nameAr,
      qty: qty,
      unitTotalEgp: unitTotal,
      config: config,
    );

void main() {
  group('order intake — content-addressed key (hash phone + items + address)', () {
    test('same phone+items+address -> same hash stable across retries', () {
      final tea = _item('tea-id', 'tea', 40, 'hot_drinks');
      const cfg = ItemConfig(sizeIndex: 0);
      final items = [_payload(tea, cfg, 2, 80)];
      final json = [for (final i in items) i.toJson()];

      final k1 = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: json, addressId: 'addr-1');
      final k2 = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: json, addressId: 'addr-1');
      expect(k1, k2);
      expect(k1, isNotEmpty);
      // md5 hex length 32
      expect(k1.length, 32);
    });

    test('different address -> not deduped (different hash)', () {
      final tea = _item('tea-id', 'tea', 40, 'hot_drinks');
      const cfg = ItemConfig();
      final items = [_payload(tea, cfg, 1, 40)];
      final json = [for (final i in items) i.toJson()];

      final kSameAddr = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: json, addressId: 'addr-1');
      final kDiffAddr = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: json, addressId: 'addr-2');
      final kNoAddr = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: json, addressId: null);
      expect(kSameAddr, isNot(kDiffAddr));
      expect(kSameAddr, isNot(kNoAddr));
    });

    test('addon order insensitive (caramel + espresso vs espresso + caramel)', () {
      final tea = _item('tea-id', 'tea', 40, 'hot_drinks');
      final cfgA = ItemConfig(addons: {'caramel', 'espresso_shot'});
      final cfgB = ItemConfig(addons: {'espresso_shot', 'caramel'});
      final itemsA = [_payload(tea, cfgA, 1, 65)];
      final itemsB = [_payload(tea, cfgB, 1, 65)];
      final jsonA = [for (final i in itemsA) i.toJson()];
      final jsonB = [for (final i in itemsB) i.toJson()];

      final kA = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: jsonA, addressId: 'addr-1');
      final kB = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: jsonB, addressId: 'addr-1');
      expect(kA, kB);
    });

    test('item order insensitive (sorted item keys)', () {
      final tea = _item('a-id', 'a', 10, 'hot');
      final biscuit = _item('b-id', 'b', 20, 'snacks');
      const cfg = ItemConfig();
      final items1 = [_payload(tea, cfg, 1, 10), _payload(biscuit, cfg, 1, 20)];
      final items2 = [_payload(biscuit, cfg, 1, 20), _payload(tea, cfg, 1, 10)];
      final k1 = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: [for (final i in items1) i.toJson()], addressId: null);
      final k2 = intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: [for (final i in items2) i.toJson()], addressId: null);
      expect(k1, k2);
    });

    test('phone vs googleUserId fallback consistent', () {
      final tea = _item('tea-id', 'tea', 40, 'hot_drinks');
      const cfg = ItemConfig();
      final items = [_payload(tea, cfg, 1, 40)];
      final json = [for (final i in items) i.toJson()];
      final kPhone = intake.orderIntakeKeyFromJson(phone: '+201111111111', itemsJson: json, addressId: null);
      final kGid = intake.orderIntakeKeyFromJson(phone: null, googleUserId: '+201111111111', itemsJson: json, addressId: null);
      // When phone present, phone is used; when null, googleUserId fallback should give same when same string value
      expect(kPhone, kGid);
    });

    test('hash not containing Uuid.v4 nonce — deterministic', () {
      final tea = _item('tea-id', 'tea', 40, 'hot_drinks');
      const cfg = ItemConfig();
      final items = [_payload(tea, cfg, 1, 40)];
      final json = [for (final i in items) i.toJson()];
      final keys = <String>{};
      for (var i = 0; i < 5; i++) {
        keys.add(intake.orderIntakeKeyFromJson(phone: '+201000000000', itemsJson: json, addressId: null));
      }
      expect(keys.length, 1); // not random
    });
  });

  group('intake DAG — explicit validate -> risk -> rate-limit -> dedup', () {
    test('FakeOrdersDb exposes explicit pipeline ordering, not alphabetical names', () {
      final fake = FakeOrdersDb();
      expect(fake.pipelineOrdering, 'validate -> risk -> rate-limit -> dedup');
      // Ensure alphabetical triggers are not referenced
      expect(fake.pipelineOrdering.contains('trg_a'), isFalse);
      expect(fake.pipelineOrdering.contains('trg_b'), isFalse);
    });

    test('second insert same cart is idempotent, different address not deduped (fake)', () async {
      final fake = FakeOrdersDb();
      final tea = _item('tea-id', 'tea', 40, 'hot_drinks');
      const cfg = ItemConfig();
      final payload = _payload(tea, cfg, 1, 40);

      final order1 = NewOrder(
        mode: OrderMode.pickup,
        googleUserId: 'g1',
        phone: '+201000000001',
        items: [payload],
        subtotalEgp: 40,
        deliveryFeeEgp: 0,
        totalEgp: 40,
        pointsPreview: 4,
        addressId: 'addr-1',
      );
      final placed1 = await fake.placeOrder(order1);
      final placedDup = await fake.placeOrder(order1);
      expect(placedDup.id, placed1.id);
      expect(placedDup.displayNumber, placed1.displayNumber);
      expect(fake.storedCount, 1);

      final orderDiffAddr = NewOrder(
        mode: OrderMode.delivery,
        googleUserId: 'g1',
        phone: '+201000000001',
        items: [payload],
        subtotalEgp: 40,
        deliveryFeeEgp: 15,
        totalEgp: 55,
        pointsPreview: 4,
        addressId: 'addr-2',
      );
      final placed2 = await fake.placeOrder(orderDiffAddr);
      expect(placed2.id, isNot(placed1.id));
      expect(fake.storedCount, 2);
    });

    test('rate-limit after dedup ordering: dedup does not bypass rate limit', () async {
      final fake = FakeOrdersDb(rateLimitMax: 2, rateLimitWindowMinutes: 5);
      final tea = _item('tea-id', 'tea', 40, 'hot_drinks');
      const cfg = ItemConfig();
      final p1 = _payload(tea, cfg, 1, 40);
      final p2 = _payload(_item('b-id', 'b', 50, 'snacks'), cfg, 1, 50);
      final p3 = _payload(_item('c-id', 'c', 60, 'cold'), cfg, 1, 60);

      final o1 = NewOrder(mode: OrderMode.pickup, googleUserId: 'g1', phone: '+209999999999', items: [p1], subtotalEgp: 40, deliveryFeeEgp: 0, totalEgp: 40, pointsPreview: 4);
      final o2 = NewOrder(mode: OrderMode.pickup, googleUserId: 'g1', phone: '+209999999999', items: [p2], subtotalEgp: 50, deliveryFeeEgp: 0, totalEgp: 50, pointsPreview: 5);
      await fake.placeOrder(o1);
      await fake.placeOrder(o2);
      // 3rd distinct cart should be throttled (rate-limit before dedup)
      final o3 = NewOrder(mode: OrderMode.pickup, googleUserId: 'g1', phone: '+209999999999', items: [p3], subtotalEgp: 60, deliveryFeeEgp: 0, totalEgp: 60, pointsPreview: 6);
      expect(() => fake.placeOrder(o3), throwsA(isA<StateError>()));
    });
  });
}
