// TDD RED for P2 staff edit delivery notes.
// Verifies StaffOrder notes field, repo updateNotes, and detail sheet editor.
// MUST fail before GREEN and pass after.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P2 staff notes editing (RED)', () {
    test('StaffOrder has notes field', () {
      final content = File('lib/data/repos/staff_orders_repository.dart').readAsStringSync();
      expect(content, contains('notes'));
      expect(content, contains('fromRow'));
    });

    test('repo has updateNotes method', () {
      final content = File('lib/data/repos/staff_orders_repository.dart').readAsStringSync();
      expect(content, anyOf([contains('updateNotes'), contains('updateOrder')]));
      expect(content, contains('notes'));
    });

    test('detail sheet contains notes editor', () {
      final content = File('lib/ui/staff/widgets/staff_order_detail_sheet.dart').readAsStringSync();
      expect(content, anyOf([contains('notes'), contains('ملاحظات'), contains('Note')]));
      expect(content, contains('TextField'));
    });
  });
}
