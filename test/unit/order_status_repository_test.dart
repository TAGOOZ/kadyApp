// Unit test for the customer orders-status slice's one-shot fetch (#006,
// audit #7): `fetchOwnOrders` must stay a bounded read — newest-first,
// filtered by google_user_id, capped at [ownOrdersFetchLimit]. The repo talks
// to Supabase directly (no seam), so the assertion runs against a real
// PostgREST wire request answered by an in-process HttpServer: no network,
// no Supabase project.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/order_status_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  final requests = <HttpRequest>[];

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request);
      final response = request.response
        ..headers.contentType = ContentType.json;
      if (request.method == 'HEAD') {
        // Head-count probes only need the content-range total.
        response.headers.set('content-range', '*/42');
      } else {
        response.write(jsonEncode([
          {
            'id': 'o1',
            'display_number': 1023,
            'mode': 'dine_in',
            'status': 'in_prep',
            'reject_reason': null,
            'items': [
              {'name_ar': 'لاتيه', 'qty': 2},
            ],
            'total': 95,
            'assigned_driver': null,
            'created_at': '2026-08-22T12:00:00Z',
          },
        ]));
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  SupabaseOrderStatusRepo repoOnProbe() =>
      SupabaseOrderStatusRepo(SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'probe-anon-key',
      ));

  group('fetchOwnOrders — bounded query modifiers on the wire (audit #7)', () {
    test('orders newest-first, filters own rows and caps at 50', () async {
      final orders = await repoOnProbe().fetchOwnOrders('u1');

      expect(requests, hasLength(1));
      final url = requests.single.uri;
      expect(url.path, '/rest/v1/orders');
      expect(url.queryParameters['google_user_id'], 'eq.u1');
      expect(url.queryParameters['order'], startsWith('created_at.desc'));
      expect(url.queryParameters['limit'], '$ownOrdersFetchLimit');
      expect(url.queryParameters['select'],
          contains('display_number')); // projected columns, not *

      // Row parsing still works end-to-end over the probe server.
      expect(orders, hasLength(1));
      expect(orders.single.id, 'o1');
      expect(orders.single.displayNumber, 1023);
      expect(orders.single.itemCount, 2);
      expect(orders.single.totalEgp, 95);
      expect(orders.single.isCompleted, isFalse);
    });
  });
}
