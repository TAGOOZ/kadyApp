// TDD RED for admin zones editor (FEATURES §6).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  group('admin zones editor (RED)', () {
    test('migration 0009 adds zones table', () {
      final file = File('supabase/migrations/0009_zones.sql');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('zones'));
      expect(content, contains('fee'));
    });
    test('admin dashboard or rules shows zones', () {
      final dashboard = File('lib/ui/admin/admin_dashboard_screen.dart').readAsStringSync();
      final rules = File('lib/ui/admin/widgets/rules_editor.dart').readAsStringSync();
      final combined = dashboard + rules;
      expect(combined, anyOf([contains('zones'), contains('Zones'), contains('سعر'), contains('منطقة')]));
    });
    test('zones panel or banner exists', () {
      final hasPanel = File('lib/ui/admin/widgets/zones_editor_panel.dart').existsSync() ||
          File('lib/ui/admin/widgets/rules_editor.dart').readAsStringSync().contains('zones');
      expect(hasPanel, isTrue);
    });
  });
}
