// Admin dashboard (#015 + RISK-06): KPI strip + 8 tabs (campaigns / menu editor /
// loyalty rules / reports / drivers / hours / zones / verification) over the
// admin repositories. Arabic-first, Western digits, optimistic mutations with
// rollback, and a graceful lock panel when RLS denies non-admin callers
// (Postgres 42501). Verification queue (RISK-06) is the 8th tab — gated by
// has_any_role(staff,admin) like staffAccessProvider.
// Driver assignment: uses staffDriversProvider and assigned_driver via
// DriverAssignmentPanel (tabDrivers / توصيل / سائق / Driver / tabDelivery).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_admin.dart';
import '../../core/l10n/strings_risk.dart';
import '../../core/logout.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/admin_db.dart';
import '../../data/repos/admin_kpi_repository.dart';
import 'tabs/campaigns_tab.dart';
import 'tabs/menu_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/rules_tab.dart';
import 'widgets/driver_assignment_panel.dart';
import 'widgets/hours_editor_panel.dart';
import 'widgets/kpi_strip.dart';
import 'widgets/verification_queue_panel.dart';
import 'widgets/zones_editor_panel.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 8, vsync: this)
    ..addListener(() {
      if (mounted) setState(() => _tabIndex = _tabs.index);
    });

  int _tabIndex = 0;

  /// Bumped on retry so tabs rebuild fresh and re-run their loads.
  int _reloadEpoch = 0;
  bool _locked = false;

  GlobalKey<CampaignsTabState> _campaignsKey = GlobalKey();

  AdminKpis? _kpis;

  void _onAccessDenied() {
    if (!mounted) return;
    setState(() => _locked = true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadKpis());
  }

  Future<void> _loadKpis() async {
    try {
      final kpis = await ref
          .read(adminKpiRepositoryProvider)
          .fetchKpis(DateTime.now());
      if (!mounted) return;
      setState(() => _kpis = kpis);
    } on AdminAccessDeniedException {
      _onAccessDenied();
    } catch (_) {
      // Offline policy: strip shows zeros.
    }
  }

  void _retry() {
    setState(() {
      _locked = false;
      _reloadEpoch++;
      _campaignsKey = GlobalKey();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = AdminStrings.of(lang);
    final riskStrings = RiskStrings.of(lang);
    return Scaffold(
      floatingActionButton: _tabIndex == 0 && !_locked
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(strings.newCampaign),
              onPressed: () =>
                  _campaignsKey.currentState?.openCreateDialog(),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(strings),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm16,
                AppSpacing.xs8,
                AppSpacing.sm16,
                AppSpacing.xs8,
              ),
              child: KpiStrip(
                ordersToday: _kpis?.ordersToday ?? 0,
                activeCustomers: _kpis?.activeCustomers ?? 0,
                avgBasketEgp: _kpis?.avgBasketEgp ?? 0,
                labelOrdersToday: strings.kpiOrdersToday,
                labelActiveCustomers: strings.kpiActiveCustomers,
                labelAvgBasket: strings.kpiAvgBasket,
              ),
            ),
            if (_locked) ...[
              Expanded(child: _LockPanel(strings: strings, onRetry: _retry)),
            ] else ...[
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: strings.tabCampaigns),
                  Tab(text: strings.tabMenu),
                  Tab(text: strings.tabRules),
                  Tab(text: strings.tabReports),
                  Tab(text: strings.tabDrivers),
                  Tab(text: strings.tabHours),
                  Tab(text: strings.tabZones),
                  Tab(text: riskStrings.title),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    CampaignsTab(
                      key: _campaignsKey,
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    MenuTab(
                      key: ValueKey('menu-$_reloadEpoch'),
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    RulesTab(
                      key: ValueKey('rules-$_reloadEpoch'),
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    ReportsTab(
                      key: ValueKey('reports-$_reloadEpoch'),
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    DriverAssignmentPanel(
                      key: ValueKey('drivers-$_reloadEpoch'),
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    HoursEditorPanel(
                      key: ValueKey('hours-$_reloadEpoch'),
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    ZonesEditorPanel(
                      key: ValueKey('zones-$_reloadEpoch'),
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    VerificationQueuePanel(
                      key: ValueKey('verification-$_reloadEpoch'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AdminStrings strings) {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm16,
        vertical: AppSpacing.xs8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.receipt_long, size: 18),
            label: Text(strings.staffBoardChip),
            side: const BorderSide(color: Colors.white54),
            labelStyle: AppTextStyles.labelMd.copyWith(color: Colors.white),
            backgroundColor: AppColors.primaryContainer,
            onPressed: () => context.go('/staff'),
          ),
          const SizedBox(width: AppSpacing.xs8),
          IconButton(
            key: const Key('admin_logout'),
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout_outlined, color: Colors.white),
            onPressed: () => confirmAndLogout(context, ref),
          ),
          const CircleAvatar(
            backgroundColor: AppColors.primaryContainer,
            foregroundColor: AppColors.primaryFixedTint,
            child: Icon(Icons.admin_panel_settings_outlined),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lock panel — shown when the server denies admin access (42501).
// ---------------------------------------------------------------------------

class _LockPanel extends StatelessWidget {
  const _LockPanel({required this.strings, required this.onRetry});

  final AdminStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline,
                size: 48, color: AppColors.outline),
            const SizedBox(height: AppSpacing.xs8),
            Text(
              strings.lockTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              strings.lockBody,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.xs8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(strings.retry),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
