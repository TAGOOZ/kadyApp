// Unit tests for the staff orders slice (#012): transition payload shape
// (orders.update patch + order_events audit row) driven against a fake
// StaffOrdersDb seam, rolling prep-time mean, items summary line, Cairo
// pickup-slot display, and the check-in visit payload including the
// loyalty-pending mapping when the direct stamp write hits RLS (42501).
// No network, no Supabase.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/staff_orders_repository.dart';
import 'package:kady_app/domain/order_status_flow.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException;

class _FakeStaffOrdersDb implements StaffOrdersDb {
  final List<Map<String, Object?>> stampRpcCalls = [];
  bool? Function(String phone, int spend)? onStampRpc;
  final orderUpdates = <MapEntry<String, Map<String, dynamic>>>[];
  final orderEvents = <Map<String, dynamic>>[];
  final visits = <Map<String, dynamic>>[];
  final staffLogs = <Map<String, dynamic>>[];
  final stampWrites = <MapEntry<String, int>>[];

  Object? visitInsertError;
  Object? stampUpdateError;
  String? ownRole = 'staff';
  String? userId = 'u1';
  int? stampMinSpend = 50;
  int? stampsOnFile = 3;
  Stream<List<Map<String, dynamic>>> watchStream = const Stream.empty();

  // Name-map fetch recording (audit #5).
  List<Map<String, dynamic>> pagePhoneRows = const [];
  List<Map<String, dynamic>> customerRowsByPhone = const [];
  Set<String>? fetchedCustomersByPhones;

  @override
  Stream<List<Map<String, dynamic>>> watchOrders() => watchStream;

  @override
  Future<List<Map<String, dynamic>>> fetchPagePhones() async => pagePhoneRows;

  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(
    Set<String> phones,
  ) async {
    fetchedCustomersByPhones = phones;
    return customerRowsByPhone;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAddresses(Set<String> ids) async =>
      const [];

  @override
  Future<void> updateOrder(
      String orderId, Map<String, dynamic> patch) async {
    orderUpdates.add(MapEntry(orderId, patch));
  }

  @override
  Future<void> insertOrderEvent(Map<String, dynamic> row) async {
    orderEvents.add(row);
  }

  @override
  Future<void> insertVisit(Map<String, dynamic> row) async {
    final error = visitInsertError;
    if (error != null) throw error;
    visits.add(row);
  }

  @override
  Future<void> insertStaffLog(Map<String, dynamic> row) async {
    staffLogs.add(row);
  }

  @override
  Future<int?> fetchStampMinSpend() async => stampMinSpend;

  @override
  Future<int?> fetchStamps(String phone) async => stampsOnFile;

  @override
  Future<void> updateStamps(String phone, int stamps) async {
    final error = stampUpdateError;
    if (error != null) throw error;
    stampWrites.add(MapEntry(phone, stamps));
  }

  @override
  Future<String?> fetchOwnRole(String googleUserId) async => ownRole;

  @override
  String? currentUserId() => userId;
  @override
  Future<bool?> applyStampRpc(String phone, int spend) async {
    stampRpcCalls.add({'phone': phone, 'spend': spend});
    if (onStampRpc != null) return onStampRpc!(phone, spend);
    return true;
  }

}

StaffOrder _order({
  required OrderWireStatus status,
  required DateTime createdAtUtc,
  String modeWire = 'dine_in',
}) {
  return StaffOrder(
    id: 'o-${status.wireName}',
    displayNumber: 1023,
    phone: '+201001234567',
    modeWire: modeWire,
    status: status,
    lines: const [OrderItemLine(name: 'لاتيه', qty: 2)],
    createdAtUtc: createdAtUtc,
  );
}

void main() {
  group('transition payload builders — patch + event row shape', () {
    test('cancel with reason writes status + trimmed reject_reason', () {
      final patch = transitionOrderPatch(
        OrderWireStatus.cancelled,
        rejectReason: '  المكونات نفدت  ',
      );
      expect(patch, {
        'status': 'cancelled',
        'reject_reason': 'المكونات نفدت',
      });
    });

    test('non-cancel transitions never carry reject_reason', () {
      expect(
        transitionOrderPatch(OrderWireStatus.accepted),
        {'status': 'accepted'},
      );
      expect(
        transitionOrderPatch(OrderWireStatus.outForDelivery),
        {'status': 'out_for_delivery'},
      );
    });

    test('event row mirrors the target status with actor staff', () {
      expect(orderEventInsertRow('abc', OrderWireStatus.inPrep), {
        'order_id': 'abc',
        'status': 'in_prep',
        'actor': 'staff',
      });
    });

    test('repo.transition writes patch then append-only event', () async {
      final db = _FakeStaffOrdersDb();
      final repo = SupabaseStaffOrdersRepo(db);

      await repo.transition('o1', OrderWireStatus.cancelled,
          rejectReason: 'خارج التغطية');

      expect(db.orderUpdates.single.key, 'o1');
      expect(db.orderUpdates.single.value, {
        'status': 'cancelled',
        'reject_reason': 'خارج التغطية',
      });
      expect(db.orderEvents.single, {
        'order_id': 'o1',
        'status': 'cancelled',
        'actor': 'staff',
      });
    });
  });

  group('averagePrepMinutes — rolling mean over in_prep only', () {
    test('mean of current prep ages, rounded', () {
      final now = DateTime.utc(2026, 8, 22, 12);
      final orders = [
        _order(status: OrderWireStatus.received, createdAtUtc: now),
        _order(status: OrderWireStatus.inPrep, createdAtUtc:
            now.subtract(const Duration(minutes: 9))),
        _order(status: OrderWireStatus.inPrep, createdAtUtc:
            now.subtract(const Duration(minutes: 10))),
        _order(status: OrderWireStatus.ready, createdAtUtc:
            now.subtract(const Duration(minutes: 99))),
      ];
      // (9 + 10) / 2 = 9.5 → rounds to 10.
      expect(averagePrepMinutes(orders, now), 10);
    });

    test('falls back when nothing is on the stove', () {
      final now = DateTime.utc(2026, 8, 22, 12);
      expect(averagePrepMinutes([], now), 8);
      expect(
        averagePrepMinutes([
          _order(status: OrderWireStatus.done, createdAtUtc: now),
        ], now),
        8,
      );
    });
  });

  group('itemsSummaryLine + parsing', () {
    test('parses the items jsonb snapshot with qty fallback', () {
      final lines = parseItemLines([
        {'name_ar': 'لاتيه', 'qty': 2},
        {'name_ar': 'كرواسون'},
      ]);
      expect(lines.map((l) => l.name), ['لاتيه', 'كرواسون']);
      expect(lines.map((l) => l.qty), [2, 1]);
      expect(itemsSummaryLine(lines), 'لاتيه ×2 · كرواسون');
    });
  });

  group('formatPickupSlotCairo + elapsed', () {
    test('summer slot renders Cairo HH:mm Western digits', () {
      expect(
        formatPickupSlotCairo(DateTime.utc(2026, 8, 22, 10, 30)),
        '13:30',
      );
    });

    test('elapsed floors at zero against clock skew', () {
      final now = DateTime.utc(2026, 8, 22, 12);
      expect(elapsedMinutesSince(now, now), 0);
      expect(
        elapsedMinutesSince(now.add(const Duration(minutes: 5)), now),
        0,
      );
      expect(
        elapsedMinutesSince(now.subtract(const Duration(minutes: 7)), now),
        7,
      );
    });
  });

  group('registerVisit — visit row, audit row, loyalty attempt', () {
    test('records visit + staff_log and stamps when spend qualifies',
        () async {
      final db = _FakeStaffOrdersDb();
      final repo = SupabaseStaffOrdersRepo(db);

      final result = await repo.registerVisit(const CheckInInput(
        phone: '+201001234567',
        spendEgp: 60,
        tableArea: 'داخل - طاولة 12',
      ));

      expect(result.loyaltyPending, isFalse);
      expect(db.visits.single, {
        'phone': '+201001234567',
        'source': 'checkin',
        'spend_egp': 60,
        'table_area': 'داخل - طاولة 12',
      });
      expect(db.staffLogs.single['action'], 'checkin');
      expect(db.staffLogs.single['target_phone'], '+201001234567');
      // Migration 0004: stamping is server-authoritative via staff_apply_stamp.
      expect(db.stampRpcCalls.single['phone'], '+201001234567');
      expect(db.stampRpcCalls.single['spend'], 60);
    });

    test('qualifying check-in delegates wrap math to the RPC', () async {
      // Migration 0004: card completion/reset lives in staff_apply_stamp;
      // the client only forwards the request.
      final db = _FakeStaffOrdersDb()..stampsOnFile = 9;
      final result = await SupabaseStaffOrdersRepo(db).registerVisit(
        const CheckInInput(phone: '+201001234567', spendEgp: 60),
      );
      expect(result.loyaltyPending, isFalse);
      expect(db.stampRpcCalls.single['spend'], 60);
      expect(db.stampWrites, isEmpty);
    });

    test('below threshold skips the stamp entirely (nothing pending)',
        () async {
      final db = _FakeStaffOrdersDb();
      final result = await SupabaseStaffOrdersRepo(db)
          .registerVisit(const CheckInInput(phone: '+201001234567',
              spendEgp: 20));

      expect(result.loyaltyPending, isFalse);
      expect(db.visits, hasLength(1));
      expect(db.stampWrites, isEmpty);
      expect(db.stampRpcCalls, isEmpty); // below threshold → no rpc
    });

    test('rpc failure → visit recorded, loyalty PENDING', () async {
      final db = _FakeStaffOrdersDb()
        ..onStampRpc = (_, _) => null; // network/missing fn
      final result = await SupabaseStaffOrdersRepo(db)
          .registerVisit(const CheckInInput(phone: '+201001234567',
              spendEgp: 80));

      expect(result.loyaltyPending, isTrue);
      expect(db.visits, hasLength(1)); // the visit itself survived
    });

    test('visit insert blocked by RLS propagates as permission failure',
        () async {
      final db = _FakeStaffOrdersDb()
        ..visitInsertError =
            const PostgrestException(code: '42501', message: 'RLS');
      await expectLater(
        SupabaseStaffOrdersRepo(db).registerVisit(const CheckInInput(
          phone: '+201001234567',
          spendEgp: 80,
        )),
        throwsA(isA<StaffPermissionException>()),
      );
      expect(db.visits, isEmpty);
    });
  });

  group('rethrowAsTyped — Postgres 42501 mapping', () {
    test('RLS denial becomes StaffPermissionException', () {
      expect(
        () => rethrowAsTyped(
            const PostgrestException(code: '42501', message: 'RLS')),
        throwsA(isA<StaffPermissionException>()),
      );
    });

    test('other Postgres errors pass through untouched', () {
      const original = PostgrestException(code: '23505', message: 'dup');
      expect(
        () => rethrowAsTyped(original),
        throwsA(same(original)),
      );
    });
  });

  group('ensureStaffAccess — profiles.role gate', () {
    test('passes for elevated staff/admin rows only', () async {
      final db = _FakeStaffOrdersDb()..ownRole = 'admin';
      await SupabaseStaffOrdersRepo(db).ensureStaffAccess();

      db.ownRole = 'customer';
      await expectLater(
        SupabaseStaffOrdersRepo(db).ensureStaffAccess(),
        throwsA(isA<StaffPermissionException>()),
      );

      db.userId = null; // signed out / guest shell
      db.ownRole = 'staff';
      await expectLater(
        SupabaseStaffOrdersRepo(db).ensureStaffAccess(),
        throwsA(isA<StaffPermissionException>()),
      );
    });
  });

  group('fetchCustomerNames — bounded phone→name map (audit #5)', () {
    test(
        'distinct phones off the ≤60-row page drive one in-filter customers read',
        () async {
      final db = _FakeStaffOrdersDb()
        ..pagePhoneRows = [
          {'phone': '+201000000001'},
          {'phone': '+201000000001'}, // duplicate collapses
          {'phone': null}, // guest order ignored
          {'phone': '+201000000002'},
        ]
        ..customerRowsByPhone = [
          {'phone': '+201000000001', 'name': 'مصطفى'},
        ];
      final repo = SupabaseStaffOrdersRepo(db);

      final names = await repo.fetchCustomerNames();

      expect(db.fetchedCustomersByPhones,
          {'+201000000001', '+201000000002'});
      expect(names, {'+201000000001': 'مصطفى'});
    });

    test('guest-only page (no phones) skips the customers query entirely',
        () async {
      final db = _FakeStaffOrdersDb()
        ..pagePhoneRows = [
          {'phone': null},
        ];

      expect(await SupabaseStaffOrdersRepo(db).fetchCustomerNames(), isEmpty);
      // Empty phone set → the adapter short-circuits before any in-filter
      // customers read is issued.
      expect(db.fetchedCustomersByPhones, isEmpty);
    });
  });

  group('streamAll + fromRow', () {
    test('maps rows and sorts newest first regardless of arrival order',
        () async {
      final db = _FakeStaffOrdersDb();
      final controller = StreamController<List<Map<String, dynamic>>>();
      db.watchStream = controller.stream;
      final repo = SupabaseStaffOrdersRepo(db);

      final emitted = <List<StaffOrder>>[];
      final sub = repo.streamAll().listen(emitted.add);
      controller.add([
        {
          'id': 'old',
          'display_number': 1001,
          'mode': 'pickup',
          'status': 'done',
          'created_at':
              DateTime.utc(2026, 8, 22, 11).toIso8601String(),
          'items': [],
        },
        {
          'id': 'new',
          'display_number': 1002,
          'mode': 'delivery',
          'status': 'new',
          'created_at':
              DateTime.utc(2026, 8, 22, 12).toIso8601String(),
          'items': [
            {'name_ar': 'لاتيه', 'qty': 2},
          ],
          'phone': '+201001234567',
          'address_id': 'a1',
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.single.map((o) => o.id).toList(), ['new', 'old']);
      expect(emitted.single.first.phone, '+201001234567');
      expect(emitted.single.first.addressId, 'a1');
      expect(emitted.single.first.lines.single.name, 'لاتيه');

      await sub.cancel();
      await controller.close();
    });
  });
}
