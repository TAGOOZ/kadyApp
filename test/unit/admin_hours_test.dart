// TDD RED for admin hours editor (FEATURES §6).
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
void main() {
  group('admin hours editor (RED)', () {
    test('migration 0008 adds hours table', () {
      final file = File('supabase/migrations/0008_hours.sql');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('hours'));
      expect(content, contains('delivery_enabled'));
    });
    test('admin dashboard contains hours tab', () {
      final content = File('lib/ui/admin/admin_dashboard_screen.dart').readAsStringSync();
      expect(content, anyOf([contains('hours'), contains('Hours'), contains('ساعات'), contains('opening')]));
    });
    test('hours panel file exists', () {
      final file = File('lib/ui/admin/widgets/hours_editor_panel.dart');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('hours'));
    });
  });
}
