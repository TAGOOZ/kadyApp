// TDD RED for P1-1 staff/admin assignment write path.
// Verifies that StaffOrdersRepo.transition correctly writes assigned_driver
// when handing a delivery to a driver, and that the DB seam receives it.
// MUST fail before GREEN and pass after.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/data/repos/staff_orders_repository.dart';
import 'package:kady_app/domain/order_status_flow.dart';

class _FakeStaffDb implements StaffOrdersDb {
  Map<String, dynamic>? lastPatch;
  String? lastOrderId;

  @override
  Future<bool?> applyStampRpc(String phone, int spend) async => true;

  @override
  Stream<List<Map<String, dynamic>>> watchOrders() => const Stream.empty();

  @override
  Future<List<Map<String, dynamic>>> fetchPagePhones() async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchCustomersByPhones(Set<String> phones) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchAddresses(Set<String> ids) async => const [];

  @override
  Future<void> updateOrder(String orderId, Map<String, dynamic> patch) async {
    lastOrderId = orderId;
    lastPatch = patch;
  }

  @override
  Future<void> insertOrderEvent(Map<String, dynamic> row) async {}

  @override
  Future<void> transitionOrder(
    String orderId,
    String status, {
    String? rejectReason,
    String? assignedDriverId,
    String actor = 'staff',
  }) async {
    lastOrderId = orderId;
    lastPatch = transitionOrderPatch(
      OrderWireStatus.fromWire(status) ?? OrderWireStatus.received,
      rejectReason: rejectReason,
      assignedDriverId: assignedDriverId,
    );
  }

  @override
  Future<void> insertVisit(Map<String, dynamic> row) async {}

  @override
  Future<void> insertStaffLog(Map<String, dynamic> row) async {}

  @override
  Future<int?> fetchStampMinSpend() async => null;

  @override
  Future<int?> fetchStamps(String phone) async => null;

  @override
  Future<void> updateStamps(String phone, int stamps) async {}

  @override
  Future<String?> fetchOwnRole(String googleUserId) async => 'staff';

  @override
  Future<List<Map<String, dynamic>>> fetchDriverProfiles() async => const [];

  @override
  String? currentUserId() => 'staff-uid';
}

void main() {
  group('P1-1 staff assigned_driver write path (RED)', () {
    test('transitionOrderPatch includes assigned_driver when supplied', () {
      final patch = transitionOrderPatch(
        OrderWireStatus.outForDelivery,
        assignedDriverId: 'driver-uuid-123',
      );
      expect(patch['status'], OrderWireStatus.outForDelivery.wireName);
      expect(patch['assigned_driver'], 'driver-uuid-123',
          reason: 'patch must contain assigned_driver for driver handover');
    });

    test('transition writes assigned_driver via DB', () async {
      final db = _FakeStaffDb();
      final repo = SupabaseStaffOrdersRepo(db);
      await repo.transition(
        'order-99',
        OrderWireStatus.outForDelivery,
        assignedDriverId: 'driver-uuid-123',
      );
      expect(db.lastOrderId, 'order-99');
      expect(db.lastPatch, isNotNull);
      expect(db.lastPatch!['assigned_driver'], 'driver-uuid-123');
      expect(db.lastPatch!['status'], OrderWireStatus.outForDelivery.wireName);
    });

    test('transition without assignedDriver does not set assigned_driver', () async {
      final db = _FakeStaffDb();
      final repo = SupabaseStaffOrdersRepo(db);
      await repo.transition('o1', OrderWireStatus.accepted);
      expect(db.lastPatch, isNotNull);
      expect(db.lastPatch!.containsKey('assigned_driver'), isFalse);
    });

    test('staff repo file contains assigned_driver assignment logic', () {
      final content = File('lib/data/repos/staff_orders_repository.dart').readAsStringSync();
      expect(content, contains('assigned_driver'),
          reason: 'staff repo must handle assigned_driver');
      expect(content, contains('assignedDriverId'),
          reason: 'transition must accept assignedDriverId param');
    });

    test('AdminOrders assignment: admin can list drivers via profiles', () {
      final content = File('lib/data/repos/admin_repositories.dart').readAsStringSync();
      // Admin should be able to fetch drivers for assignment picker (either here or new repo).
      // For RED we check for driver-related fetch; will fail until implemented.
      // Alternative is StaffOrdersDb.fetchDrivers — check either file.
      final staffContent = File('lib/data/repos/staff_orders_repository.dart').readAsStringSync();
      final hasDriverFetch = content.contains('fetchDrivers') ||
          staffContent.contains('fetchDrivers') ||
          content.contains("role'") && content.contains('driver');
      expect(hasDriverFetch, isTrue,
          reason: 'assignment picker needs driver list fetch (profiles where role=driver)');
    });
  });
}
