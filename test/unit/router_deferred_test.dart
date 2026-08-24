// ignore_for_file: unused_import
// TDD RED for ADR-0011 deferred routes.
// Verifies router.dart uses deferred imports for heavy screens and
// FutureBuilder(loadLibrary) wrappers, while keeping home/menu/profile eager.
// This test MUST fail before the GREEN step (eager imports) and pass after.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Import one deferred library to verify loadLibrary is callable at runtime.
// This mirrors the prefix style used in lib/core/router.dart (ADR-0011).
import 'package:kady_app/ui/games/spinner/spinner_screen.dart' deferred as spinner;
// Heavy routes with extensions are verified via file-content checks only
// to avoid the "extension cannot be imported deferred" compile restriction.
import 'package:kady_app/ui/games/scratch/scratch_screen.dart' deferred as scratch;
import 'package:kady_app/ui/staff/staff_board_screen.dart' deferred as staff_board;
import 'package:kady_app/ui/lookup/customer_lookup_screen.dart' deferred as lookup;
import 'package:kady_app/ui/driver/driver_home_screen.dart' deferred as driver_home;
import 'package:kady_app/ui/admin/admin_dashboard_screen.dart' deferred as admin_dashboard;

void main() {
  group('router deferred imports (ADR-0011)', () {
    late String content;

    setUpAll(() {
      final file = File('lib/core/router.dart');
      expect(file.existsSync(), isTrue,
          reason: 'lib/core/router.dart must exist');
      content = file.readAsStringSync();
    });

    test('deferred libraries expose loadLibrary (runtime check)', () async {
      // These expectations prove the deferred prefix is correctly wired:
      // loadLibrary must be a callable Future<void> Function().
      expect(spinner.loadLibrary, isA<Function>());
      expect(scratch.loadLibrary, isA<Function>());
      expect(staff_board.loadLibrary, isA<Function>());
      expect(lookup.loadLibrary, isA<Function>());
      expect(driver_home.loadLibrary, isA<Function>());
      expect(admin_dashboard.loadLibrary, isA<Function>());

      // Actually await one to prove it compiles & links.
      await spinner.loadLibrary();
      expect(true, isTrue);
    });

    test('heavy routes use deferred imports', () {
      expect(
        content,
        contains(
            "import '../ui/games/spinner/spinner_screen.dart' deferred as spinner"),
      );
      expect(
        content,
        contains(
            "import '../ui/games/match/match_screen.dart' deferred as match"),
      );
      expect(
        content,
        contains(
            "import '../ui/games/scratch/scratch_screen.dart' deferred as scratch"),
      );
      expect(
        content,
        contains(
            "import '../ui/quests/quests_badges_screen.dart' deferred as quests"),
      );
      expect(
        content,
        contains(
            "import '../ui/staff/staff_board_screen.dart' deferred as staff_board"),
      );
      expect(
        content,
        contains(
            "import '../ui/lookup/customer_lookup_screen.dart' deferred as lookup"),
      );
      expect(
        content,
        contains(
            "import '../ui/driver/driver_home_screen.dart' deferred as driver_home"),
      );
      expect(
        content,
        contains(
            "import '../ui/admin/admin_dashboard_screen.dart' deferred as admin_dashboard"),
      );
    });

    test('heavy routes builders use loadLibrary via FutureBuilder', () {
      expect(content, contains('spinner.loadLibrary'));
      expect(content, contains('match.loadLibrary'));
      expect(content, contains('scratch.loadLibrary'));
      expect(content, contains('quests.loadLibrary'));
      expect(content, contains('staff_board.loadLibrary'));
      expect(content, contains('lookup.loadLibrary'));
      expect(content, contains('driver_home.loadLibrary'));
      expect(content, contains('admin_dashboard.loadLibrary'));
      expect(content, contains('FutureBuilder'));
      // Ensure each heavy route path still exists.
      expect(content, contains("path: '/games/spinner'"));
      expect(content, contains("path: '/games/match'"));
      expect(content, contains("path: '/games/scratch'"));
      expect(content, contains("path: '/games/quests'"));
      expect(content, contains("path: '/staff'"));
      expect(content, contains("path: '/staff/lookup'"));
      expect(content, contains("path: '/driver'"));
      expect(content, contains("path: '/admin'"));
      // Deferred widgets referenced via prefix.
      expect(content, contains('spinner.SpinnerScreen'));
      expect(content, contains('match.MatchScreen'));
      expect(content, contains('scratch.ScratchScreen'));
      expect(content, contains('quests.QuestsBadgesScreen'));
      expect(content, contains('staff_board.StaffBoardScreen'));
      expect(content, contains('lookup.CustomerLookupScreen'));
      expect(content, contains('driver_home.DriverHomeScreen'));
      expect(content, contains('admin_dashboard.AdminDashboardScreen'));
    });

    test('home/menu/profile remain eager (inside shell)', () {
      expect(content, contains("import '../ui/home/home_screen.dart';"));
      expect(content, contains("import '../ui/menu/menu_screen.dart';"));
      expect(content, contains("import '../ui/profile/profile_screen.dart';"));
      // They must NOT be deferred (check precise import path to avoid substring false positives).
      expect(content, isNot(contains("import '../ui/home/home_screen.dart' deferred")));
      expect(content, isNot(contains("import '../ui/menu/menu_screen.dart' deferred")));
      expect(content, isNot(contains("import '../ui/profile/profile_screen.dart' deferred")));
      // Shell still uses eager widgets.
      expect(content, contains('HomeScreen'));
      expect(content, contains('MenuScreen'));
      expect(content, contains('ProfileScreen'));
    });

    test('eager heavy imports are removed', () {
      // After GREEN there should be no eager (non-deferred) imports for heavy screens.
      // We check that the old eager form without "deferred" does not appear.
      expect(
        content,
        isNot(contains(
            "import '../ui/games/spinner/spinner_screen.dart';")),
      );
      expect(
        content,
        isNot(contains(
            "import '../ui/games/match/match_screen.dart';")),
      );
      expect(
        content,
        isNot(contains(
            "import '../ui/games/scratch/scratch_screen.dart';")),
      );
      expect(
        content,
        isNot(contains(
            "import '../ui/quests/quests_badges_screen.dart';")),
      );
      expect(
        content,
        isNot(contains(
            "import '../ui/staff/staff_board_screen.dart';")),
      );
      expect(
        content,
        isNot(contains(
            "import '../ui/lookup/customer_lookup_screen.dart';")),
      );
      expect(
        content,
        isNot(contains(
            "import '../ui/driver/driver_home_screen.dart';")),
      );
      expect(
        content,
        isNot(contains(
            "import '../ui/admin/admin_dashboard_screen.dart';")),
      );
    });

    test('preserves go_router, Riverpod, theme and shell', () {
      expect(content, contains('go_router'));
      expect(content, contains('flutter_riverpod'));
      // router.dart itself may not directly import app_theme.dart, but theme
      // must remain project-wide; check that NavigationBar/go_router wiring persists.
      expect(content, contains('GoRoute'));
      expect(content, contains('StatefulShellRoute'));
      expect(content, contains('StatefulShellBranch'));
      expect(content, contains("path: '/home'"));
      expect(content, contains("path: '/menu'"));
      expect(content, contains("path: '/profile'"));
      expect(content, contains('NavigationBar'));
      // Ensure theme file still exists project-wide (ADR-0011 heritage hearth).
      expect(File('lib/core/theme/app_theme.dart').existsSync(), isTrue);
    });
  });
}
