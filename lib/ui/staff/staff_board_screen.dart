// Staff orders board (#012, FEATURES §6): live realtime queue (ADR-0006)
// with a rolling prep-time strip, per-mode filter tabs with counts, status
// action cards, a walk-in check-in sheet and the new-order snackbar banner.
// Server permission comes from profiles.role — without it the screen renders
// the full-screen lock panel with the elevation hint (docs/SUPABASE_SETUP.md).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_lookup.dart';
import '../../core/l10n/strings_staff.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/staff_orders_repository.dart';
import '../../domain/order_status_flow.dart';
import 'widgets/checkin_sheet.dart';
import 'widgets/order_card.dart';
import 'widgets/staff_order_detail_sheet.dart';

enum StaffFilter { all, dineIn, pickup, delivery }

class StaffFilterNotifier extends Notifier<StaffFilter> {
  @override
  StaffFilter build() => StaffFilter.all;

  void select(StaffFilter filter) => state = filter;
}

final staffFilterProvider = NotifierProvider<StaffFilterNotifier, StaffFilter>(
    StaffFilterNotifier.new);

class StaffBoardScreen extends ConsumerStatefulWidget {
  const StaffBoardScreen({super.key});

  @override
  ConsumerState<StaffBoardScreen> createState() => _StaffBoardScreenState();
}

class _StaffBoardScreenState extends ConsumerState<StaffBoardScreen> {
  Timer? _tickTimer;
  DateTime _nowUtc = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    // Keeps the elapsed chips + rolling prep mean honest between realtime
    // pushes; cancelled in dispose so tests never leak timers.
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _nowUtc = DateTime.now().toUtc());
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onTransition(
    StaffOrder order,
    OrderWireStatus toStatus, {
    String? rejectReason,
  }) async {
    final strings = StaffStrings.of(ref.read(localeNotifierProvider));
    try {
      await ref
          .read(staffOrdersRepoProvider)
          .transition(order.id, toStatus, rejectReason: rejectReason);
    } on StaffPermissionException {
      _showSnack(strings.lockTitle);
    } catch (_) {
      _showSnack(strings.transitionFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = StaffStrings.of(lang);
    final access = ref.watch(staffAccessProvider);

    // Realtime insert detection → طلب جديد #NNNN 🛎️ (ADR-0006 in-app only).
    ref.listen<AsyncValue<List<StaffOrder>>>(staffOrdersStreamProvider,
        (previous, next) {
      final previousIds = previous?.value?.map((o) => o.id).toSet();
      final orders = next.value;
      if (orders == null || previousIds == null) return;
      for (final order in orders) {
        if (!previousIds.contains(order.id)) {
          _showSnack(strings.newOrder(order.displayNumber));
          break;
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(strings.boardTitle),
        actions: [
          // حساب العميل — customer lookup + manual rewards (#013).
          IconButton(
            tooltip:
                LookupStrings.of(lang).screenTitle,
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => context.push('/staff/lookup'),
          ),
          IconButton(
            tooltip: strings.checkInTooltip,
            icon: const Icon(Icons.how_to_reg_outlined),
            onPressed: () => _openCheckIn(strings),
          ),
          const Padding(
            padding: EdgeInsetsDirectional.only(end: AppSpacing.xs8),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primaryContainer,
              child:
                  Icon(Icons.person_outline, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
      body: access.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => error is StaffPermissionException
            ? _LockPanel(
                strings: strings,
                onRetry: () => ref.invalidate(staffAccessProvider),
              )
            : _RetryPanel(
                strings: strings,
                onRetry: () => ref.invalidate(staffAccessProvider),
              ),
        data: (_) => _BoardBody(
          strings: strings,
          lang: lang,
          nowUtc: _nowUtc,
          onTransition: (order, to, {rejectReason}) =>
              _onTransition(order, to, rejectReason: rejectReason),
        ),
      ),
    );
  }

  Future<void> _openCheckIn(StaffStrings strings) async {
    final repo = ref.read(staffOrdersRepoProvider);
    final recorded = await showCheckInSheet(
      context,
      strings: strings,
      onSubmit: repo.registerVisit,
    );
    if (!mounted || recorded == null) return;
    _showSnack(
        recorded.loyaltyPending ? strings.visitPending : strings.visitOk);
  }
}

// ---------------------------------------------------------------------------
// Board body — visible only after the permission probe passes
// ---------------------------------------------------------------------------

class _BoardBody extends ConsumerWidget {
  const _BoardBody({
    required this.strings,
    required this.lang,
    required this.nowUtc,
    required this.onTransition,
  });

  final StaffStrings strings;
  final AppLang lang;
  final DateTime nowUtc;

  /// Card-level transition with the resolved [StaffOrder].
  final Future<void> Function(
    StaffOrder order,
    OrderWireStatus toStatus, {
    String? rejectReason,
  }) onTransition;

  static int _countFor(List<StaffOrder> orders, StaffFilter filter) =>
      switch (filter) {
        StaffFilter.all => orders.length,
        StaffFilter.dineIn =>
          orders.where((o) => o.modeWire == 'dine_in').length,
        StaffFilter.pickup => orders.where((o) => o.modeWire == 'pickup').length,
        StaffFilter.delivery =>
          orders.where((o) => o.modeWire == 'delivery').length,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(staffOrdersStreamProvider);
    final namesAsync = ref.watch(staffCustomerNamesProvider);
    final filter = ref.watch(staffFilterProvider);

    return Column(
      children: [
        _AvgPrepStrip(
          strings: strings,
          minutes: averagePrepMinutes(ordersAsync.value ?? const [], nowUtc),
        ),
        _FilterTabs(
          strings: strings,
          active: filter,
          counts: {
            for (final f in StaffFilter.values)
              f: _countFor(ordersAsync.value ?? const [], f),
          },
          onSelect: (selected) =>
              ref.read(staffFilterProvider.notifier).select(selected),
        ),
        Expanded(
          child: ordersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _RetryPanel(
              strings: strings,
              onRetry: () => ref.invalidate(staffOrdersStreamProvider),
            ),
            data: (orders) {
              final visible = filter == StaffFilter.all
                  ? orders
                  : orders.where((o) {
                      return switch (filter) {
                        StaffFilter.dineIn => o.modeWire == 'dine_in',
                        StaffFilter.pickup => o.modeWire == 'pickup',
                        StaffFilter.delivery => o.modeWire == 'delivery',
                        StaffFilter.all => true,
                      };
                    }).toList();
              if (visible.isEmpty) {
                return Center(child: Text(strings.emptyBoard));
              }
              final names = namesAsync.value ?? const <String, String>{};
              return ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.gutter16),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final order = visible[index];
                  final addressText = order.addressId == null
                      ? null
                      : ref.watch(staffAddressTextProvider(order.addressId!)).value;
                  final customerName =
                      order.phone == null ? null : names[order.phone];
                  return OrderCard(
                    order: order,
                    strings: strings,
                    lang: lang,
                    nowUtc: nowUtc,
                    customerName: customerName,
                    addressText: addressText,
                    onTransition: (to, {rejectReason}) =>
                        onTransition(order, to, rejectReason: rejectReason),
                    onTap: () => showStaffOrderDetailSheet(
                      context,
                      order: order,
                      customerName: customerName,
                      addressText: addressText,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Dark strip under the header: متوسط وقت التحضير X دقايق.
class _AvgPrepStrip extends StatelessWidget {
  const _AvgPrepStrip({required this.strings, required this.minutes});

  final StaffStrings strings;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primaryContainer,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter16, vertical: AppSpacing.xs8),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined,
              size: 18, color: AppColors.parchment),
          const SizedBox(width: AppSpacing.xs8),
          Text(
            strings.avgPrep(minutes),
            style:
                AppTextStyles.bodySm.copyWith(color: AppColors.parchment),
          ),
        ],
      ),
    );
  }
}

/// الكل(n) · صالة(n) · استلام(n) · توصيل(n) — active deep-forest pill.
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.strings,
    required this.active,
    required this.counts,
    required this.onSelect,
  });

  final StaffStrings strings;
  final StaffFilter active;
  final Map<StaffFilter, int> counts;
  final ValueChanged<StaffFilter> onSelect;

  String _label(StaffFilter filter) => switch (filter) {
        StaffFilter.all => strings.tabAll,
        StaffFilter.dineIn => strings.tabDineIn,
        StaffFilter.pickup => strings.tabPickup,
        StaffFilter.delivery => strings.tabDelivery,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gutter16, vertical: AppSpacing.xs8),
        children: [
          for (final filter in StaffFilter.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs8),
              child: _FilterPill(
                label: '${_label(filter)} (${counts[filter] ?? 0})',
                active: filter == active,
                onTap: () => onSelect(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.parchment,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.labelMd.copyWith(
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AppColors.coffeeBean,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen panels
// ---------------------------------------------------------------------------

/// قفل 🔒 بلا صلاحية موظف — profiles.role not elevated; points at the SQL.
class _LockPanel extends StatelessWidget {
  const _LockPanel({required this.strings, required this.onRetry});

  final StaffStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline,
                size: 56, color: AppColors.primary.withValues(alpha: 0.7)),
            const SizedBox(height: AppSpacing.sm16),
            Text(strings.lockTitle,
                style: AppTextStyles.titleMd, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs8),
            Text(
              strings.lockHint,
              style: AppTextStyles.bodySm
                   .copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm16),
            FilledButton.tonal(onPressed: onRetry, child: Text(strings.retryCta)),
          ],
        ),
      ),
    );
  }
}

class _RetryPanel extends StatelessWidget {
  const _RetryPanel({required this.strings, required this.onRetry});

  final StaffStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_outlined,
              size: 48, color: AppColors.outline),
          const SizedBox(height: AppSpacing.sm16),
          Text(strings.loadFailed, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm16),
          FilledButton(onPressed: onRetry, child: Text(strings.retryCta)),
        ],
      ),
    );
  }
}
