// TDD RED for P1-3 dead /auth stub removal.
// Verifies lib/core/router.dart no longer exposes the placeholder
// AuthStubScreen and that the stub file itself is removed.
// MUST fail before GREEN (stub present) and pass after.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('router dead /auth stub removal (P1-3)', () {
    late String routerContent;

    setUpAll(() {
      final file = File('lib/core/router.dart');
      expect(file.existsSync(), isTrue,
          reason: 'lib/core/router.dart must exist');
      routerContent = file.readAsStringSync();
    });

    test('router does not import AuthStubScreen', () {
      expect(
        routerContent,
        isNot(contains("import '../ui/screens/auth_stub_screen.dart'")),
        reason: 'router.dart must not import AuthStubScreen after P1-3',
      );
      expect(
        routerContent,
        isNot(contains('AuthStubScreen')),
        reason: 'router.dart must not reference AuthStubScreen',
      );
    });

    test('router does not define GoRoute path /auth stub', () {
      // The valid route is /auth/phone — the bare /auth placeholder must be gone.
      expect(routerContent, contains("path: '/auth/phone'"),
          reason: '/auth/phone must remain');
      // Stub was GoRoute(path: '/auth', builder: AuthStubScreen) — ensure bare path is gone.
      // Use exact match with trailing comma+newline: "path: '/auth'," only matches bare stub,
      // not '/auth/phone'.
      expect(
        routerContent,
        isNot(contains("path: '/auth',")),
        reason: 'bare GoRoute path /auth must be removed (keep /auth/phone)',
      );
      // The TODO that marked the stub should also be gone.
      expect(
        routerContent,
        isNot(contains('TODO(slice-004)')),
        reason: 'TODO(slice-004) marker must be removed with stub',
      );
    });

    test('AuthStubScreen file is removed', () {
      final stub = File('lib/ui/screens/auth_stub_screen.dart');
      expect(stub.existsSync(), isFalse,
          reason:
              'lib/ui/screens/auth_stub_screen.dart must be deleted after P1-3');
    });
  });
}
