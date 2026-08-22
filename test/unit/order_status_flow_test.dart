// Pure flow logic tests (#006): per-mode step sequences, current-index
// lookup, and the cancelled terminal case. No network, no Supabase.
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/domain/order_status_flow.dart';

void main() {
  group('stepsFor — sequence per service mode (§3.6)', () {
    test('dine-in ends at تم التقديم', () {
      final steps = OrderStatusFlow.stepsFor(FlowMode.dineIn);
      expect(
        steps.map((s) => s.status.wireName),
        ['new', 'accepted', 'in_prep', 'ready', 'done'],
      );
      expect(steps.first.labelAr, 'تم الاستلام');
      expect(steps[2].labelAr, 'قيد التحضير');
      expect(steps.last.labelAr, 'تم التقديم');
    });

    test('pickup ends at جاهز للاستلام — no served step', () {
      final steps = OrderStatusFlow.stepsFor(FlowMode.pickup);
      expect(
        steps.map((s) => s.status.wireName),
        ['new', 'accepted', 'in_prep', 'ready'],
      );
      expect(steps.last.labelAr, 'جاهز للاستلام');
      expect(
        steps.where((s) => s.status == OrderWireStatus.done),
        isEmpty,
      );
    });

    test('delivery adds في الطريق إليك before تم التوصيل', () {
      final steps = OrderStatusFlow.stepsFor(FlowMode.delivery);
      expect(
        steps.map((s) => s.status.wireName),
        ['new', 'accepted', 'in_prep', 'ready', 'out_for_delivery', 'done'],
      );
      expect(steps[4].labelAr, 'في الطريق إليك');
      expect(steps.last.labelAr, 'تم التوصيل');
    });

    test('every step carries ar/en labels and an icon', () {
      for (final mode in FlowMode.values) {
        for (final step in OrderStatusFlow.stepsFor(mode)) {
          expect(step.labelAr, isNotEmpty);
          expect(step.labelEn, isNotEmpty);
          expect(step.icon.codePoint, greaterThan(0));
        }
      }
    });
  });

  group('indexOfCurrent', () {
    test('maps each wire status to its slot per mode', () {
      expect(
        OrderStatusFlow.indexOfCurrent(
          FlowMode.dineIn,
          OrderWireStatus.inPrep,
        ),
        2,
      );
      expect(
        OrderStatusFlow.indexOfCurrent(FlowMode.dineIn, OrderWireStatus.done),
        4,
      );
      // Pickup never serves: `done` is outside its flow.
      expect(
        OrderStatusFlow.indexOfCurrent(FlowMode.pickup, OrderWireStatus.done),
        -1,
      );
      expect(
        OrderStatusFlow.indexOfCurrent(FlowMode.pickup, OrderWireStatus.ready),
        3,
      );
      expect(
        OrderStatusFlow.indexOfCurrent(
          FlowMode.delivery,
          OrderWireStatus.outForDelivery,
        ),
        4,
      );
      expect(
        OrderStatusFlow.indexOfCurrent(FlowMode.delivery, OrderWireStatus.done),
        5,
      );
    });

    test('cancelled and unknown statuses render the terminal row (-1)', () {
      for (final mode in FlowMode.values) {
        expect(
          OrderStatusFlow.indexOfCurrent(mode, OrderWireStatus.cancelled),
          -1,
        );
      }
    });
  });

  group('stepFor + helpers', () {
    test('returns null for out-of-flow statuses', () {
      expect(
        OrderStatusFlow.stepFor(FlowMode.pickup, OrderWireStatus.cancelled),
        isNull,
      );
      expect(
        OrderStatusFlow.stepFor(
          FlowMode.pickup,
          OrderWireStatus.outForDelivery,
        ),
        isNull,
      );
      final step =
          OrderStatusFlow.stepFor(FlowMode.delivery, OrderWireStatus.ready);
      expect(step?.labelEn, 'Ready');
    });

    test('wire round-trip: fromWire ∘ wireName is identity', () {
      for (final status in OrderWireStatus.values) {
        expect(OrderWireStatus.fromWire(status.wireName), status);
      }
      expect(OrderWireStatus.fromWire('bogus'), isNull);
    });

    test('FlowMode.fromWire matches the DB vocabulary', () {
      expect(FlowMode.fromWire('dine_in'), FlowMode.dineIn);
      expect(FlowMode.fromWire('pickup'), FlowMode.pickup);
      expect(FlowMode.fromWire('delivery'), FlowMode.delivery);
      expect(FlowMode.fromWire(null), isNull);
    });
  });
}
