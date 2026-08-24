// TDD RED for admin driver assignment panel.
// Verifies that AdminDashboardScreen exposes a delivery/driver assignment UI
// that lists delivery orders and allows assigning a driver via the staff seam.
// MUST fail before GREEN and pass after.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('admin driver assignment panel (RED)', () {
    test('admin_dashboard_screen contains assignment tab', () {
      final content = File('lib/ui/admin/admin_dashboard_screen.dart').readAsStringSync();
      expect(content, contains('Driver'));
      expect(content, anyOf([contains('assigned_driver'), contains('assignDriver'), contains('staffDriversProvider')]));
      expect(content, contains('Tab('));
      expect(content, anyOf([contains('tabDelivery'), contains('tabAssignment'), contains('توصيل'), contains('سائق')]));
    });

    test('admin assignment widget file exists', () {
      final file = File('lib/ui/admin/widgets/driver_assignment_panel.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('staffDriversProvider'));
      expect(content, contains('assigned_driver'));
      expect(content, contains('staffOrdersRepoProvider'));
    });

    test('admin strings contain assignment labels', () {
      final content = File('lib/core/l10n/strings_admin.dart').readAsStringSync();
      expect(content, anyOf([contains('driver'), contains('Driver'), contains('سائق')]));
    });
  });
}
