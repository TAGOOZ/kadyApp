// TDD RED for P1-1 driver assigned_driver filtering.
// Verifies that DriverOrdersRepo.streamAssigned returns only orders
// where assigned_driver == currentUserId (server-assigned), not all
// out_for_delivery. MUST fail before GREEN (unfiltered) and pass after.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/data/repos/driver_orders_repository.dart';

class _FakeDriverOrdersDb implements DriverOrdersDb {
  final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  String? _currentUserId;

  void setCurrentUserId(String? id) => _currentUserId = id;

  void emitRows(List<Map<String, dynamic>> rows) => controller.add(rows);

  @override
  Stream<List<Map<String, dynamic>>> watchAssigned() => controller.stream;

  @override
  Future<List<Map<String, dynamic>>> fetchDoneDeliveries() async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchAddresses(Set<String> ids) async =>
      const [];

  @override
  Future<void> updateOrder(String orderId, Map<String, dynamic> patch) async {}

  @override
  Future<void> insertOrderEvent(Map<String, dynamic> row) async {}

  @override
  Future<void> transitionOrder(
    String orderId,
    String status, {
    String? actor,
  }) async {
    await updateOrder(orderId, {'status': status});
    await insertOrderEvent(driverOrderEventRow(orderId, status));
  }

  @override
  Future<List<String>> fetchEventStatuses(String orderId) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchCustomers() async => const [];

  @override
  Future<String?> fetchOwnRole(String googleUserId) async => 'driver';

  @override
  Future<Map<String, dynamic>?> fetchDriverProfile(String userId) async =>
      null;

  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(
          Set<String> phones) async =>
      const [];

  @override
  String? currentUserId() => _currentUserId;
}

Map<String, dynamic> _row({
  required String id,
  String? assignedDriver,
  String status = 'out_for_delivery',
}) {
  return {
    'id': id,
    'display_number': 1000 + int.parse(id.substring(1)),
    'phone': '+201001234567',
    'status': status,
    'mode': 'delivery',
    'items': [
      {'name_ar': 'لاتيه', 'qty': 1},
    ],
    'total': 90,
    'notes': null,
    'address_id': 'addr-1',
    'assigned_driver': assignedDriver,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
}

void main() {
  group('P1-1 driver assigned_driver filtering (RED)', () {
    test('streamAssigned passes currentUserId to watchAssigned and filters', () async {
      final db = _FakeDriverOrdersDb()..setCurrentUserId('driver-a');
      final repo = SupabaseDriverOrdersRepo(db);

      final emitted = <List<DriverOrder>>[];
      final sub = repo.streamAssigned().listen(emitted.add);
      addTearDown(() => sub.cancel());

      // Emit two rows: one assigned to driver-a, one to driver-b, one unassigned
      db.emitRows([
        _row(id: 'o1', assignedDriver: 'driver-a'),
        _row(id: 'o2', assignedDriver: 'driver-b'),
        _row(id: 'o3', assignedDriver: null),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Repo must emit only driver-a order (unassigned must not show to any driver)
      expect(emitted, isNotEmpty);
      final last = emitted.last;
      expect(last.map((o) => o.id), contains('o1'));
      expect(last.map((o) => o.id), isNot(contains('o2')),
          reason: 'driver-b order must not leak to driver-a');
      expect(last.map((o) => o.id), isNot(contains('o3')),
          reason: 'unassigned order must not show to any driver');
      expect(last.length, 1,
          reason: 'only driver-a assignment must be visible');
    });

    test('streamAssigned returns empty when not signed in (null uid)', () async {
      final db = _FakeDriverOrdersDb()..setCurrentUserId(null);
      final repo = SupabaseDriverOrdersRepo(db);
      final emitted = <List<DriverOrder>>[];
      final sub = repo.streamAssigned().listen(emitted.add);
      addTearDown(() => sub.cancel());
      db.emitRows([_row(id: 'o1', assignedDriver: 'driver-a')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // When uid null, repo should not pass filter but emit empty (or watch with null returns empty)
      // For TDD we expect either empty emission or no leak. Current buggy impl emits the row regardless.
      // After GREEN it should emit empty or filtered.
      if (emitted.isEmpty) {
        expect(true, isTrue);
      } else {
        expect(emitted.last, isEmpty,
            reason: 'guest/null driver must see no deliveries');
      }
    });

    test('SupabaseDriverOrdersDb.watchAssigned file contains assigned_driver filter',
        () async {
      final file = File('lib/data/repos/driver_orders_repository.dart');
      final content = file.readAsStringSync();
      expect(content, contains('assigned_driver'),
          reason: 'watchAssigned must filter by assigned_driver');
      expect(content, contains('currentUserId'),
          reason: 'watchAssigned must use currentUserId for filtering');
      expect(content, contains("eq('assigned_driver'"),
          reason: 'Supabase stream must eq assigned_driver');
    });
  });
}
