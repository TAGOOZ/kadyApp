// Barrel for the admin slice (ARCH-02 split).
// Keeps `import 'admin_repositories.dart'` working while the implementation
// lives in focused files: admin_db / admin_campaign_repository /
// admin_menu_repository / admin_rules_repository / admin_kpi_repository.
//
// New code should import the specific file directly; this barrel is for
// backward compat and will stay until callers migrate.
export 'admin_db.dart';
export 'admin_campaign_repository.dart';
export 'admin_kpi_repository.dart';
export 'admin_menu_repository.dart';
export 'admin_rules_repository.dart';
