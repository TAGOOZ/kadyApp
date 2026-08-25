// TDD RED for P2 ETA slider (FEATURES §6).
// Verifies expected_ready_at column, StaffOrder field, repo patch, and
// detail sheet slider. MUST fail before GREEN and pass after.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P2 ETA slider (RED)', () {
    test('migration 0007 adds expected_ready_at column', () {
      final file = File('supabase/migrations/0007_staff_eta.sql');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('expected_ready_at'));
      expect(content, contains('timestamptz'));
    });

    test('StaffOrder has expectedReadyAt field', () {
      // ARCH-02 split: StaffOrder lives in staff_orders_models.dart, repo in
      // staff_orders_repository.dart — check either (barrel covers both).
      final repoContent = File('lib/data/repos/staff_orders_repository.dart').readAsStringSync();
      final modelsContent = File('lib/data/repos/staff_orders_models.dart').readAsStringSync();
      final barrelContent = File('lib/data/repos/staff_orders.dart').existsSync()
          ? File('lib/data/repos/staff_orders.dart').readAsStringSync()
          : '';
      final combined = repoContent + modelsContent + barrelContent;
      expect(combined, contains('expectedReadyAt'));
      expect(combined, contains('expected_ready_at'));
      expect(combined, contains('fromRow'));
    });

    test('repo has method to set expected ready time', () {
      final content = File('lib/data/repos/staff_orders_repository.dart').readAsStringSync();
      expect(content, anyOf([contains('expectedReadyAt'), contains('ExpectedReady'), contains('setExpectedReady')]));
      expect(content, contains('expected_ready_at'));
    });

    test('detail sheet contains ETA slider', () {
      final content = File('lib/ui/staff/widgets/staff_order_detail_sheet.dart').readAsStringSync();
      expect(content, anyOf([contains('expected_ready_at'), contains('expectedReadyAt'), contains('ETA'), contains('Slider')]));
      expect(content, anyOf([contains('Slider'), contains('expectedReady'), contains('متوقع')]));
    });

    test('order_card shows expected time chip when set', () {
      final content = File('lib/ui/staff/widgets/order_card.dart').readAsStringSync();
      expect(content, anyOf([contains('expected_ready_at'), contains('expectedReadyAt'), contains('متوقع')]));
    });
  });
}
