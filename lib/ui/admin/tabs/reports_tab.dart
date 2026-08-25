// Reports tab (ARCH-02 split): extracted from admin_dashboard_screen.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_db.dart';
import '../../../data/repos/admin_kpi_repository.dart';
import '../widgets/kpi_strip.dart';
import '../widgets/mode_share_chart.dart';

class ReportsTab extends ConsumerStatefulWidget {
  const ReportsTab({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<ReportsTab> createState() => ReportsTabState();
}

class ReportsTabState extends ConsumerState<ReportsTab> {
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
