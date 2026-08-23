// Unit tests for the driver orders slice (#014): transition payloads/event
// shapes (accept & picked_up are events only, delivered flips status 'done'
// then appends its event), history mapping + Cairo-day cash summary math
// (ADR-0009 boundary case), notes [REDEEMED…] strip helper, Google Maps URL
// encoding (Arabic address), stepper derivation from order_events and the
// profiles.role access gate. All against a fake DriverOrdersDb seam — no
// network, no Supabase.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/driver_orders_repository.dart';
import 'package:kady_app/domain/order_status_flow.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class _FakeDriverOrdersDb implements DriverOrdersDb {
  final ops = <String>[]; // 'update' | 'event' in exact call order
  final orderUpdates = <MapEntry<String, Map<String, dynamic>>>[];
  final orderEvents = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> doneDeliveries = const [];
  final Map<String, List<String>> eventsByOrder = {};
  Object? customersError;
  String? ownRole = 'driver';
  String? userId = 'u1';
  Stream<List<Map<String, dynamic>>> watchStream = const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> watchAssigned() => watchStream;

  @override
  Future<List<Map<String, dynamic>>> fetchDoneDeliveries() async =>
      doneDeliveries;

  @override
  Future<List<Map<String, dynamic>>> fetchAddresses(Set<String> ids) async => [
    for (final id in ids) {'id': id, 'address_text': 'عنوان $id'},
  ];

  @override
  Future<void> updateOrder(String orderId, Map<String, dynamic> patch) async {
    ops.add('update');
    orderUpdates.add(MapEntry(orderId, patch));
  }

  @override
  Future<void> insertOrderEvent(Map<String, dynamic> row) async {
    ops.add('event');
    orderEvents.add(row);
  }

  @override
  Future<List<String>> fetchEventStatuses(String orderId) async =>
      eventsByOrder[orderId] ?? const [];

  @override
  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    final error = customersError;
    if (error != null) throw error;
    return const [
      {'phone': '+201001234567', 'name': 'مصطفى'},
    ];
  }

  @override
  Future<String?> fetchOwnRole(String googleUserId) async => ownRole;

  @override
  String? currentUserId() => userId;
}

Map<String, dynamic> _doneDeliveryRow({
  required String id,
  required int number,
  required DateTime createdAtUtc,
  int totalEgp = 75,
}) {
  return {
    'id': id,
    'display_number': number,
    'phone': '+201001234567',
    'mode': 'delivery',
    'status': 'done',
    'items': [
      {'name_ar': 'لاتيه', 'qty': 2},
    ],
    'total': totalEgp,
    'address_id': 'a-$id',
    'created_at': createdAtUtc.toIso8601String(),
  };
}

void main() {
  group('transition payloads — accept / pickedUp / delivered', () {
    test(
      'accept writes ONLY an informational event, no status change',
      () async {
        final db = _FakeDriverOrdersDb();
        await SupabaseDriverOrdersRepo(db).accept('o1');

        expect(
          db.orderUpdates,
          isEmpty,
        ); // orders.status stays out_for_delivery
        expect(db.orderEvents.single, {
          'order_id': 'o1',
          'status': 'accepted',
          'actor': 'driver',
        });
      },
    );

    test('markPickedUp writes ONLY an event, no status change', () async {
      final db = _FakeDriverOrdersDb();
      await SupabaseDriverOrdersRepo(db).markPickedUp('o1');

      expect(db.orderUpdates, isEmpty);
      expect(db.orderEvents.single, {
        'order_id': 'o1',
        'status': 'picked_up',
        'actor': 'driver',
      });
    });

    test('markDelivered flips status to done THEN appends the event', () async {
      final db = _FakeDriverOrdersDb();
      await SupabaseDriverOrdersRepo(db).markDelivered('o1');

      expect(db.ops, ['update', 'event']);
      expect(db.orderUpdates.single.key, 'o1');
      expect(db.orderUpdates.single.value, {'status': 'done'});
      expect(db.orderEvents.single, {
        'order_id': 'o1',
        'status': 'done',
        'actor': 'driver',
      });
    });

    test(
      'RLS denial on the event insert maps to the typed exception',
      () async {
        // order_events writes need elevation; a bare driver row hits 42501.
        final db = _FailingEventDb();
        await expectLater(
          SupabaseDriverOrdersRepo(db).accept('o1'),
          throwsA(isA<DriverPermissionException>()),
        );
      },
    );
  });

  group('history + day summary', () {
    test(
      'fetchHistory maps rows newest-first as delivered by the seam',
      () async {
        final db = _FakeDriverOrdersDb()
          ..doneDeliveries = [
            _doneDeliveryRow(
              id: 'old',
              number: 1001,
              createdAtUtc: DateTime.utc(2026, 8, 20, 9),
            ),
            _doneDeliveryRow(
              id: 'new',
              number: 1007,
              createdAtUtc: DateTime.utc(2026, 8, 22, 11),
            ),
          ];
        final history = await SupabaseDriverOrdersRepo(db).fetchHistory();

        expect(history.map((o) => o.id), ['old', 'new']);
        expect(history.first.displayNumber, 1001);
        expect(history.first.totalEgp, 75);
        expect(history.first.status, OrderWireStatus.done);
        expect(history.first.lines.single.name, 'لاتيه');
      },
    );

    test(
      'todayDeliverySummary counts ONLY same-Cairo-day rows (UTC+3)',
      () async {
        // "Today" = 2026-08-22 on the Cairo wall clock (summer → UTC+3).
        final nowUtc = DateTime.utc(2026, 8, 22, 12, 30);
        final history = [
          // Cairo 15:00 Aug 22 ✓
          DriverOrder.fromRow(
            _doneDeliveryRow(
              id: 'a',
              number: 1001,
              createdAtUtc: DateTime.utc(2026, 8, 22, 12),
              totalEgp: 90,
            ),
          ),
          // Cairo 02:00 Aug 22 ✓ (early-morning delivery)
          DriverOrder.fromRow(
            _doneDeliveryRow(
              id: 'b',
              number: 1002,
              createdAtUtc: DateTime.utc(2026, 8, 21, 23),
              totalEgp: 60,
            ),
          ),
          // UTC 21:00 Aug 22 → Cairo 00:00 Aug 23 ✗ (tomorrow locally)
          DriverOrder.fromRow(
            _doneDeliveryRow(
              id: 'c',
              number: 1003,
              createdAtUtc: DateTime.utc(2026, 8, 22, 21),
              totalEgp: 120,
            ),
          ),
          // Cairo Aug 20 ✗
          DriverOrder.fromRow(
            _doneDeliveryRow(
              id: 'd',
              number: 1004,
              createdAtUtc: DateTime.utc(2026, 8, 20, 10),
              totalEgp: 50,
            ),
          ),
        ];

        final summary = todayDeliverySummary(history, nowUtc);
        expect(summary.deliveries, 2);
        expect(summary.collectedEgp, 150); // 90 + 60
      },
    );

    test('empty history sums to zero', () {
      final summary = todayDeliverySummary(
        const [],
        DateTime.utc(2026, 8, 22, 12),
      );
      expect(summary.deliveries, 0);
      expect(summary.collectedEgp, 0);
    });
  });

  group('stripRedeemedPrefix — notes decoration', () {
    test('strips the [REDEEMED:type:cost] prefix and trims', () {
      expect(
        stripRedeemedPrefix('[REDEEMED:free_drink:200] اتصل قبل الوصول'),
        'اتصل قبل الوصول',
      );
    });

    test('plain notes pass through untouched', () {
      expect(
        stripRedeemedPrefix('برج 5 — الدور الثالث'),
        'برج 5 — الدور الثالث',
      );
    });

    test('redemption-only or null notes collapse to empty', () {
      expect(stripRedeemedPrefix('[REDEEMED:free_snack:150]'), '');
      expect(stripRedeemedPrefix(null), '');
      expect(stripRedeemedPrefix('   '), '');
    });
  });

  group('buildMapsUrl — Arabic address encoding', () {
    test(
      'percent-encodes Arabic and round-trips through Uri.decodeComponent',
      () {
        const address = 'القاهرة الجديدة، شارع التسعين، التجمع الخامس';
        final url = buildMapsUrl(address);

        expect(
          url,
          startsWith('https://www.google.com/maps/search/?api=1&query='),
        );
        expect(url, isNot(contains(' '))); // spaces must be encoded
        expect(Uri.decodeComponent(url.split('query=').last), address);
      },
    );

    test('latin addresses ride along unchanged after the query key', () {
      expect(
        buildMapsUrl('Nasr City'),
        'https://www.google.com/maps/search/?api=1&query=Nasr%20City',
      );
    });
  });

  group('driverProgressFrom — stepper derivation from events', () {
    test('terminal done status wins regardless of events', () {
      expect(
        driverProgressFrom(OrderWireStatus.done, const []),
        DriverStep.delivered,
      );
    });

    test('out_for_delivery climbs with the highest recorded event', () {
      const status = OrderWireStatus.outForDelivery;
      expect(driverProgressFrom(status, const []), isNull);
      expect(
        driverProgressFrom(status, const ['accepted']),
        DriverStep.accepted,
      );
      expect(
        driverProgressFrom(status, const ['accepted', 'picked_up']),
        DriverStep.pickedUp,
      );
      // accepted may be missing when events aren't readable — picked_up alone.
      expect(
        driverProgressFrom(status, const ['picked_up']),
        DriverStep.pickedUp,
      );
    });
  });

  group('streamAssigned — realtime feed mapping', () {
    test('maps rows and sorts newest first', () async {
      final db = _FakeDriverOrdersDb();
      final controller = StreamController<List<Map<String, dynamic>>>();
      db.watchStream = controller.stream;
      final repo = SupabaseDriverOrdersRepo(db);

      Map<String, dynamic> row(String id, int number, DateTime created) => {
        'id': id,
        'display_number': number,
        'mode': 'delivery',
        'status': 'out_for_delivery',
        'items': [
          {'name_ar': 'كرواسون', 'qty': 1},
        ],
        'total': 45,
        'address_id': 'addr-1',
        'notes': '[REDEEMED:free_topping:100] جرس الباب بايظ',
        'created_at': created.toIso8601String(),
      };

      final emitted = <List<DriverOrder>>[];
      final sub = repo.streamAssigned().listen(emitted.add);
      controller.add([
        row('old', 1001, DateTime.utc(2026, 8, 22, 10)),
        row('new', 1009, DateTime.utc(2026, 8, 22, 12)),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.single.map((o) => o.id), ['new', 'old']);
      expect(emitted.single.last.notesDisplayAfterStrip, 'جرس الباب بايظ');
      expect(emitted.single.last.addressId, 'addr-1');

      await sub.cancel();
      await controller.close();
    });
  });

  group('fetchCustomerNames — best-effort under driver RLS', () {
    test(
      'returns {} instead of failing when customers SELECT is blocked',
      () async {
        // The real adapter converts 42501 before it reaches the repo.
        final db = _FakeDriverOrdersDb()
          ..customersError = const DriverPermissionException();
        expect(
          await SupabaseDriverOrdersRepo(db).fetchCustomerNames(),
          const <String, String>{},
        );
      },
    );

    test('maps phone → name when readable (elevated admin)', () async {
      final db = _FakeDriverOrdersDb()..ownRole = 'admin';
      expect(await SupabaseDriverOrdersRepo(db).fetchCustomerNames(), {
        '+201001234567': 'مصطفى',
      });
    });
  });

  group('ensureDriverAccess — profiles.role gate', () {
    test('passes for elevated driver/admin rows only', () async {
      final db = _FakeDriverOrdersDb()..ownRole = 'driver';
      await SupabaseDriverOrdersRepo(db).ensureDriverAccess();

      db.ownRole = 'admin';
      await SupabaseDriverOrdersRepo(db).ensureDriverAccess();

      db.ownRole = 'staff'; // staff ≠ driver
      await expectLater(
        SupabaseDriverOrdersRepo(db).ensureDriverAccess(),
        throwsA(isA<DriverPermissionException>()),
      );

      db.userId = null; // signed out / guest shell
      db.ownRole = 'driver';
      await expectLater(
        SupabaseDriverOrdersRepo(db).ensureDriverAccess(),
        throwsA(isA<DriverPermissionException>()),
      );
    });
  });

  group('rethrowAsTyped — Postgres 42501 mapping', () {
    test('RLS denial becomes DriverPermissionException', () {
      expect(
        () => rethrowAsTyped(
          const PostgrestException(code: '42501', message: 'RLS'),
        ),
        throwsA(isA<DriverPermissionException>()),
      );
    });

    test('other Postgres errors pass through untouched', () {
      const original = PostgrestException(code: '23505', message: 'dup');
      expect(() => rethrowAsTyped(original), throwsA(same(original)));
    });
  });
}

/// Db whose event inserts always fail — mirrors the real adapter converting
/// a bare-driver-role 42501 into the typed exception before it reaches us.
class _FailingEventDb extends _FakeDriverOrdersDb {
  @override
  Future<void> insertOrderEvent(Map<String, dynamic> row) async {
    throw const DriverPermissionException();
  }
}

extension on DriverOrder {
  /// Test-local convenience mirroring the UI's strip step.
  String get notesDisplayAfterStrip => stripRedeemedPrefix(notes);
}
