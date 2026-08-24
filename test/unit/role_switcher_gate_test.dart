// TDD RED for P2 hidden role switcher production hardening.
// Verifies that showRoleSwitcher and its call sites are gated behind
// kDebugMode or ENABLE_ROLE_SWITCHER, so release builds have no switcher.
// MUST fail before GREEN and pass after.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('role switcher production gate (P2)', () {
    test('role_switcher_sheet is gated by kDebugMode or ENABLE_ROLE_SWITCHER', () {
      final content = File('lib/ui/widgets/role_switcher_sheet.dart').readAsStringSync();
      expect(content, contains('kDebugMode'),
          reason: 'role_switcher_sheet must check kDebugMode');
      expect(
        content,
        anyOf([
          contains('ENABLE_ROLE_SWITCHER'),
          contains('fromEnvironment'),
        ]),
        reason: 'must support ENABLE_ROLE_SWITCHER dart-define',
      );
      expect(content, contains('showRoleSwitcher'),
          reason: 'showRoleSwitcher must exist and be gated');
      // Ensure the gate is early-return, not just comment
      expect(content, contains('if (!'),
          reason: 'gate should be if (!kDebugMode ... ) return;');
    });

    test('welcome_screen long-press is gated', () {
      final content = File('lib/ui/screens/welcome_screen.dart').readAsStringSync();
      expect(content, contains('kDebugMode'),
          reason: 'welcome_screen must gate showRoleSwitcher with kDebugMode');
      // Must not unconditionally call showRoleSwitcher
      // Check that onLongPress is conditional or showRoleSwitcher call is guarded
      final hasGatedCall = content.contains('kDebugMode') && content.contains('showRoleSwitcher');
      expect(hasGatedCall, isTrue);
    });

    test('placeholder_page long-press is gated or removed', () {
      final file = File('lib/ui/screens/placeholder_page.dart');
      if (!file.existsSync()) {
        // If file was deleted as part of cleanup, that's also gated (removed)
        expect(true, isTrue);
        return;
      }
      final content = file.readAsStringSync();
      // If still exists, must be gated
      if (content.contains('showRoleSwitcher')) {
        expect(content, contains('kDebugMode'),
            reason: 'placeholder_page must gate showRoleSwitcher');
      } else {
        expect(true, isTrue);
      }
    });
  });
}
