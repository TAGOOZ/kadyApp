// Admin dashboard (#015): KPI strip + 7 tabs (campaigns / menu editor /
// loyalty rules / reports / drivers / hours / zones) over the admin repositories. Arabic-first,
// Western digits, optimistic mutations with rollback, and a graceful
// lock panel when RLS denies non-admin callers (Postgres 42501).
// Driver assignment: uses staffDriversProvider and assigned_driver via
// DriverAssignmentPanel (tabDrivers / توصيل / سائق / Driver / tabDelivery).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_admin.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/admin_repositories.dart';
import '../../domain/loyalty_controller.dart';
import 'widgets/campaign_card.dart';
import 'widgets/driver_assignment_panel.dart';
import 'widgets/hours_editor_panel.dart';
import 'widgets/kpi_strip.dart';
import 'widgets/menu_editor_sheet.dart';
import 'widgets/mode_share_chart.dart';
import 'widgets/rules_editor.dart';
import 'widgets/zones_editor_panel.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen>
    with TickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 7, vsync: this)
    ..addListener(() {
      if (mounted) setState(() => _tabIndex = _tabs.index);
    });

  late final AdminStrings strings =
      AdminStrings.of(ref.read(localeNotifierProvider));

  int _tabIndex = 0;

  /// Bumped on retry so tabs rebuild fresh and re-run their loads.
  int _reloadEpoch = 0;
  bool _locked = false;

  GlobalKey<_CampaignsTabState> _campaignsKey = GlobalKey();

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
            _buildHeader(),
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
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _CampaignsTab(
                      key: _campaignsKey,
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    _MenuTab(
                      key: ValueKey('menu-$_reloadEpoch'),
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    _RulesTab(
                      key: ValueKey('rules-$_reloadEpoch'),
                      strings: strings,
                      onAccessDenied: _onAccessDenied,
                    ),
                    _ReportsTab(
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
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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

// ---------------------------------------------------------------------------
// Shared tab plumbing
// ---------------------------------------------------------------------------

void _showErrorToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ---------------------------------------------------------------------------
// الحملات tab
// ---------------------------------------------------------------------------

class _CampaignsTab extends ConsumerStatefulWidget {
  const _CampaignsTab({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<_CampaignsTab> createState() => _CampaignsTabState();
}

class _CampaignsTabState extends ConsumerState<_CampaignsTab> {
  List<Campaign>? _campaigns;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final campaigns =
          await ref.read(campaignRepositoryProvider).listAll();
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _loading = false;
      });
    } on AdminAccessDeniedException {
      widget.onAccessDenied();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Campaign campaign, bool active) async {
    final index = _campaigns!.indexOf(campaign);
    setState(() => _campaigns![index] = _copyWith(campaign, active: active));
    try {
      await ref.read(campaignRepositoryProvider).toggleActive(campaign, active);
    } catch (_) {
      if (!mounted) return;
      setState(() => _campaigns![index] = campaign);
      _showErrorToast(context, widget.strings.revertedError);
    }
  }

  Campaign _copyWith(Campaign c, {bool? active}) => Campaign(
        id: c.id,
        kind: c.kind,
        active: active ?? c.active,
        nameAr: c.nameAr,
        startsAt: c.startsAt,
        endsAt: c.endsAt,
      );

  Future<void> openCreateDialog() async {
    final result = await showCampaignDialog(
      context: context,
      strings: widget.strings,
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(campaignRepositoryProvider).create(
            kind: result.kind,
            nameAr: result.nameAr,
            startsAt: result.startsAt,
            endsAt: result.endsAt,
          );
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
    }
    await _load();
  }

  Future<void> _edit(Campaign campaign) async {
    final result = await showCampaignDialog(
      context: context,
      strings: widget.strings,
      initial: campaign,
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(campaignRepositoryProvider).updateDates(
            campaign.id,
            kind: result.kind,
            nameAr: result.nameAr,
            startsAt: result.startsAt,
            endsAt: result.endsAt,
          );
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
    }
    await _load();
  }

  Future<void> _delete(Campaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.deleteCampaignTitle),
        content: Text(widget.strings.deleteCampaignBodyFn(
            campaign.nameAr?.isNotEmpty == true ? campaign.nameAr! : widget.strings.kindLabel(campaign.kind))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(widget.strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(campaignRepositoryProvider).delete(campaign.id);
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final campaigns = _campaigns ?? const <Campaign>[];
    if (campaigns.isEmpty) {
      return Center(child: Text(widget.strings.noData));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        itemCount: campaigns.length,
        itemBuilder: (context, index) {
          final campaign = campaigns[index];
          return CampaignCard(
            campaign: campaign,
            strings: widget.strings,
            onToggleActive: (active) => _toggle(campaign, active),
            onEdit: () => _edit(campaign),
            onDelete: () => _delete(campaign),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// القائمة tab
// ---------------------------------------------------------------------------

class _MenuTab extends ConsumerStatefulWidget {
  const _MenuTab({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<_MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends ConsumerState<_MenuTab> {
  List<AdminCategory>? _categories;
  List<AdminMenuItem>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final catalog =
          await ref.read(adminMenuRepositoryProvider).listCatalog();
      if (!mounted) return;
      setState(() {
        _categories = catalog.categories;
        _items = catalog.items;
        _loading = false;
      });
    } on AdminAccessDeniedException {
      widget.onAccessDenied();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setAvailability(AdminMenuItem item, bool available) async {
    final index = _items!.indexOf(item);
    setState(() {
      _items![index] = _withAvailability(item, available);
    });
    try {
      await ref
          .read(adminMenuRepositoryProvider)
          .setAvailability(item.id, available);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items![index] = item);
      _showErrorToast(context, widget.strings.revertedError);
    }
  }

  AdminMenuItem _withAvailability(AdminMenuItem item, bool available) =>
      AdminMenuItem(
        id: item.id,
        slug: item.slug,
        nameAr: item.nameAr,
        nameEn: item.nameEn,
        descAr: item.descAr,
        descEn: item.descEn,
        priceEgp: item.priceEgp,
        isAvailable: available,
        sort: item.sort,
        categoryId: item.categoryId,
        categorySlug: item.categorySlug,
        categoryNameAr: item.categoryNameAr,
        imageUrl: item.imageUrl,
      );

  Future<void> _confirmDelete(AdminMenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.deleteItemTitle),
        content: Text(
          widget.strings.deleteItemBodyFn(item.nameAr),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(widget.strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final payload = item.toPayload();
    final index = _items!.indexOf(item);
    setState(() => _items!.removeAt(index));
    try {
      await ref.read(adminMenuRepositoryProvider).deleteItem(item.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items!.insert(index, item));
      _showErrorToast(context, widget.strings.revertedError);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(widget.strings.deleteItemTitle),
          action: SnackBarAction(
            label: widget.strings.undo,
            onPressed: () async {
              try {
                await ref
                    .read(adminMenuRepositoryProvider)
                    .reinsertRow(payload);
              } catch (_) {}
              await _load();
            },
          ),
        ),
      );
  }

  Future<void> _openEditor({AdminMenuItem? initial}) async {
    final categories = _categories ?? const <AdminCategory>[];
    final draft = await showMenuEditorSheet(
      context,
      strings: widget.strings,
      categories: categories,
      initial: initial,
    );
    if (draft == null || !mounted) return;
    try {
      await ref
          .read(adminMenuRepositoryProvider)
          .upsertItem(draft, id: initial?.id);
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _items ?? const <AdminMenuItem>[];
    if (items.isEmpty) {
      return Center(child: Text(widget.strings.noData));
    }
    // Group by category preserving catalog order.
    final groups = <String?, List<AdminMenuItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.categorySlug, () => []).add(item);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(widget.strings.addItem),
              onPressed: () => _openEditor(),
            ),
          ),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs8, bottom: 4),
              child: Text(
                entry.value.first.categoryNameAr ?? entry.key ?? '',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.secondary,
                    ),
              ),
            ),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final item in entry.value)
                    ListTile(
                      dense: true,
                      leading: item.imageUrl == null || item.imageUrl!.isEmpty
                          ? const Icon(Icons.image_outlined, size: 20, color: AppColors.outline)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                item.imageUrl!,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 20, color: AppColors.outline),
                              ),
                            ),
                      title: Text(
                        item.nameAr,
                        style: TextStyle(
                          color:
                              item.isAvailable ? null : AppColors.textMuted,
                          decoration: item.isAvailable
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(
                        '${item.priceEgp} ${widget.strings.currencySuffix}',
                      ),
                      onLongPress: () => _confirmDelete(item),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: item.isAvailable,
                            onChanged: (value) =>
                                _setAvailability(item, value),
                          ),
                          IconButton(
                            tooltip: widget.strings.edit,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: () => _openEditor(initial: item),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs8),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// القواعد tab
// ---------------------------------------------------------------------------

class _RulesTab extends ConsumerStatefulWidget {
  const _RulesTab({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<_RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends ConsumerState<_RulesTab> {
  Map<String, dynamic>? _values;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final values = await ref.read(rulesRepositoryProvider).fetchAll();
      if (!mounted) return;
      setState(() {
        _values = values;
        _loading = false;
      });
    } on AdminAccessDeniedException {
      widget.onAccessDenied();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save(String key, Object value) async {
    try {
      await ref.read(rulesRepositoryProvider).save(key, value);
      if (!mounted) return;
      setState(() => _values?[key] = value);
      // Push fresh config into the live loyalty engine.
      try {
        await ref.read(loyaltyProvider.notifier).refreshConfig();
      } catch (_) {}
      if (!mounted) return;
      _showErrorToast(context, widget.strings.saved);
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final values = _values ?? const <String, dynamic>{};
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: RulesEditor(
          strings: widget.strings,
          values: values,
          onSave: _save,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// التقارير tab
// ---------------------------------------------------------------------------

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  Map<String, int>? _modeCounts;
  ({String nameAr, int qty})? _topItem;
  AdminKpis? _kpis;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final kpiRepo = ref.read(adminKpiRepositoryProvider);
      final now = DateTime.now();
      final results = await Future.wait([
        kpiRepo.fetchKpis(now),
        kpiRepo.fetchRecentOrders(now),
      ]);
      if (!mounted) return;
      setState(() {
        _kpis = results[0] as AdminKpis;
        final recent = results[1] as List<Map<String, dynamic>>;
        _modeCounts = computeModeCounts(recent);
        _topItem = computeTopItem(recent);
        _loading = false;
      });
    } on AdminAccessDeniedException {
      widget.onAccessDenied();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final strings = widget.strings;
    final counts = _modeCounts ?? const {'dine_in': 0, 'pickup': 0, 'delivery': 0};
    final topItem = _topItem;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs8),
              child: ModeShareChart(
                counts: counts,
                labelDineIn: strings.modeDineIn,
                labelPickup: strings.modePickup,
                labelDelivery: strings.modeDelivery,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: Text(strings.kpiOrdersToday),
                  trailing: Text(
                    (_kpis?.ordersToday ?? 0).toString(),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AppColors.primary),
                  ),
                ),
                ListTile(
                  dense: true,
                  title: Text(strings.kpiAvgBasket),
                  trailing: Text(
                    '${KpiStrip.formatAmount(_kpis?.avgBasketEgp ?? 0)} ${strings.currencySuffix}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AppColors.primary),
                  ),
                ),
                ListTile(
                  dense: true,
                  title: Text(strings.topItemLabel),
                  trailing: Text(
                    topItem == null
                        ? strings.noData
                        : '${topItem.nameAr} ×${topItem.qty}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
