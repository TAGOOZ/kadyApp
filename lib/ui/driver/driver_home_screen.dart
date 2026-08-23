// Driver shell (#014, FEATURES §7): a minimal two-tab app — طلباتي (live
// realtime feed of delivery orders out for delivery, ADR-0006) and السجل
// (completed deliveries + Cairo-day cash summary). The order detail is a
// full-screen route with a branded map placeholder (directions URL copied to
// clipboard — no url_launcher this slice), customer block, items summary,
// the horizontal three-step stepper and a sticky bottom button that advances
// step-by-step. Server permission comes from profiles.role — without it the
// screen renders the full-screen lock panel (docs/SUPABASE_SETUP.md).
// Driver identity stub: fixed كريم م. until admin assignment exists.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_driver.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/driver_orders_repository.dart';
import '../../data/repos/orders_repository.dart' show cairoUtcOffset;
import 'widgets/delivery_progress_bar.dart';
import 'widgets/driver_order_card.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = DriverStrings.of(lang);
    final access = ref.watch(driverAccessProvider);

    // Realtime insert detection → توصيلة جديدة 🛵 (ADR-0006 in-app only).
    ref.listen<AsyncValue<List<DriverOrder>>>(driverAssignedStreamProvider, (
      previous,
      next,
    ) {
      final previousIds = previous?.value?.map((o) => o.id).toSet();
      final orders = next.value;
      if (orders == null || previousIds == null) return;
      for (final order in orders) {
        if (!previousIds.contains(order.id)) {
          _showSnack(strings.newAssignment);
          break;
        }
      }
    });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(strings.homeTitle),
          actions: [
            const Padding(
              padding: EdgeInsetsDirectional.only(end: AppSpacing.xs8),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primaryContainer,
                child: Icon(Icons.moped_outlined, size: 20),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm16),
              child: Center(
                child: Text(
                  strings.driverNameStub,
                  style: AppTextStyles.labelMd.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: AppTextStyles.bodySm.copyWith(
              fontWeight: FontWeight.w600,
            ),
            tabs: [
              Tab(text: strings.tabMyDeliveries),
              Tab(text: strings.tabHistory),
            ],
          ),
        ),
        body: access.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => error is DriverPermissionException
              ? _LockPanel(
                  strings: strings,
                  onRetry: () => ref.invalidate(driverAccessProvider),
                )
              : _RetryPanel(
                  strings: strings,
                  onRetry: () => ref.invalidate(driverAccessProvider),
                ),
          data: (_) => TabBarView(
            children: [
              _AssignedTab(strings: strings, lang: lang),
              _HistoryTab(strings: strings, lang: lang),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// طلباتي tab — live feed of out-for-delivery orders
// ---------------------------------------------------------------------------

class _AssignedTab extends ConsumerWidget {
  const _AssignedTab({required this.strings, required this.lang});

  final DriverStrings strings;
  final AppLang lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedAsync = ref.watch(driverAssignedStreamProvider);

    return assignedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _RetryPanel(
        strings: strings,
        onRetry: () => ref.invalidate(driverAssignedStreamProvider),
      ),
      data: (orders) {
        if (orders.isEmpty) {
          return Center(
            child: Text(strings.emptyAssigned, textAlign: TextAlign.center),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.gutter16),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            final addressText = order.addressId == null
                ? null
                : ref.watch(driverAddressTextProvider(order.addressId!)).value;
            return DriverOrderCard(
              order: order,
              strings: strings,
              addressText: addressText,
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => _DriverOrderDetailScreen(
                    order: order,
                    strings: strings,
                    lang: lang,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// السجل tab — completed deliveries + Cairo-day cash summary
// ---------------------------------------------------------------------------

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.strings, required this.lang});

  final DriverStrings strings;
  final AppLang lang;

  /// Cairo wall-clock `HH:mm`, Western digits (ADR-0009).
  String _cairoHHmm(DateTime utc) {
    final local = utc.add(cairoUtcOffset(utc));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(driverHistoryProvider);

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _RetryPanel(
        strings: strings,
        onRetry: () => ref.invalidate(driverHistoryProvider),
      ),
      data: (history) {
        if (history.isEmpty) {
          return Center(
            child: Text(strings.emptyHistory, textAlign: TextAlign.center),
          );
        }
        final nowUtc = DateTime.now().toUtc();
        final summary = todayDeliverySummary(history, nowUtc);
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.primaryContainer,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.gutter16,
                vertical: AppSpacing.xs8,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 18,
                    color: AppColors.parchment,
                  ),
                  const SizedBox(width: AppSpacing.xs8),
                  Expanded(
                    child: Text(
                      strings.daySummary(
                        summary.deliveries,
                        summary.collectedEgp,
                      ),
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.parchment,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter16,
                  AppSpacing.xs8,
                  AppSpacing.gutter16,
                  AppSpacing.gutter16,
                ),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final order = history[index];
                  final addressText = order.addressId == null
                      ? null
                      : ref
                            .watch(driverAddressTextProvider(order.addressId!))
                            .value;
                  return DriverHistoryRow(
                    order: order,
                    strings: strings,
                    timeLabel: _cairoHHmm(order.createdAtUtc),
                    addressText: addressText,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Detail — full-screen route pushed with the order object
// ---------------------------------------------------------------------------

class _DriverOrderDetailScreen extends ConsumerStatefulWidget {
  const _DriverOrderDetailScreen({
    required this.order,
    required this.strings,
    required this.lang,
  });

  final DriverOrder order;
  final DriverStrings strings;
  final AppLang lang;

  @override
  ConsumerState<_DriverOrderDetailScreen> createState() =>
      _DriverOrderDetailScreenState();
}

class _DriverOrderDetailScreenState
    extends ConsumerState<_DriverOrderDetailScreen> {
  DriverStep? _step;
  bool _busy = false;
  Map<String, String> _customerNames = const {};

  @override
  void initState() {
    super.initState();
    _hydrateStep();
    _hydrateNames();
  }

  /// Stepper starts from the append-only events already on file (e.g. the
  /// driver re-opened the app mid-flow); falls back to "nothing done yet"
  /// when events aren't readable/available.
  Future<void> _hydrateStep() async {
    try {
      final statuses = await ref
          .read(driverOrdersRepoProvider)
          .fetchEventStatuses(widget.order.id);
      if (!mounted) return;
      setState(() {
        _step ??= driverProgressFrom(widget.order.status, statuses);
      });
    } catch (_) {
      // Events stay unreadable under current RLS — start at zero locally.
    }
  }

  Future<void> _hydrateNames() async {
    try {
      final names = await ref
          .read(driverOrdersRepoProvider)
          .fetchCustomerNames();
      if (!mounted) return;
      setState(() => _customerNames = names);
    } catch (_) {
      // Decorative only — phone stays visible either way.
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _advance() async {
    if (_busy || _step == DriverStep.delivered) return;
    setState(() => _busy = true);
    final repo = ref.read(driverOrdersRepoProvider);
    try {
      switch (_step) {
        case null:
          await repo.accept(widget.order.id);
          setState(() => _step = DriverStep.accepted);
        case DriverStep.accepted:
          await repo.markPickedUp(widget.order.id);
          setState(() => _step = DriverStep.pickedUp);
        case DriverStep.pickedUp:
          await repo.markDelivered(widget.order.id);
          setState(() => _step = DriverStep.delivered);
        case DriverStep.delivered:
          break;
      }
    } on DriverPermissionException {
      _showSnack(widget.strings.lockTitle);
    } catch (_) {
      _showSnack(widget.strings.transitionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyDirections(String address) async {
    await Clipboard.setData(ClipboardData(text: buildMapsUrl(address)));
    if (!mounted) return;
    _showSnack(widget.strings.linkCopied);
  }

  String get _addressFull {
    final addressId = widget.order.addressId;
    if (addressId == null) return widget.strings.addressMissing;
    final text = ref.watch(driverAddressTextProvider(addressId)).value;
    return (text == null || text.trim().isEmpty)
        ? widget.strings.addressMissing
        : text.trim();
  }

  String get _notesDisplay {
    final notes = stripRedeemedPrefix(widget.order.notes);
    return notes.isEmpty ? widget.strings.noNotes : notes;
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final order = widget.order;
    final step = _step;

    final completedCount = switch (step) {
      null => 0,
      DriverStep.accepted => 1,
      DriverStep.pickedUp => 2,
      DriverStep.delivered => 3,
    };

    final buttonLabel = switch (step) {
      null => strings.actionAccept,
      DriverStep.accepted => strings.actionPickedUp,
      DriverStep.pickedUp => strings.actionDelivered,
      DriverStep.delivered => strings.deliveredDone,
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('#${order.displayNumber}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter16),
        children: [
          // Map placeholder card — branded parchment illustration with 📍
          // pins; directions hand off as a copied Google Maps URL.
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.parchment,
              borderRadius: BorderRadius.circular(AppRadii.lg16),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm16),
            child: Stack(
              children: [
                const PositionedDirectional(
                  start: 12,
                  top: 18,
                  child: Icon(
                    Icons.place_outlined,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
                const PositionedDirectional(
                  end: 24,
                  bottom: 22,
                  child: Icon(
                    Icons.place,
                    size: 36,
                    color: AppColors.secondary,
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('☕ 📍 🛵'),
                      const SizedBox(height: 6),
                      Text(
                        strings.mapTitle,
                        style: AppTextStyles.labelMd.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.coffeeBean,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: () => _copyDirections(_addressFull),
              icon: const Icon(Icons.directions_outlined, size: 20),
              label: Text(strings.openDirections),
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            ),
          ),

          // Customer block — name+phone row (tap → snackbar MVP), full
          // address, delivery notes stripped of the [REDEEMED…] prefix.
          Card(
            margin: const EdgeInsets.only(top: AppSpacing.xs8),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.md8),
                    onTap: () => _showSnack(strings.callComingSoon),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.parchment,
                            child: const Icon(
                              Icons.person_outline,
                              size: 22,
                              color: AppColors.coffeeBean,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs8 + 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _customerNameFor(order.phone),
                                  style: AppTextStyles.bodyLg.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (order.phone != null)
                                  Text(
                                    order.phone!,
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.call_outlined,
                            size: 22,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: AppSpacing.sm16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 20,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_addressFull, style: AppTextStyles.bodyLg),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.sticky_note_2_outlined,
                        size: 20,
                        color: AppColors.outline,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${strings.deliveryNotesLabel}: ',
                                style: AppTextStyles.bodySm.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.coffeeBean,
                                ),
                              ),
                              TextSpan(
                                text: _notesDisplay,
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Items summary + total cash.
          Card(
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs8),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.orderItemsLabel,
                    style: AppTextStyles.labelMd.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.coffeeBean,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...[
                    for (final line in order.lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                line.qty <= 1
                                    ? line.name
                                    : '${line.name} ×${line.qty}',
                                style: AppTextStyles.bodySm,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const Divider(height: AppSpacing.sm16),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      strings.cash(order.totalEgp ?? 0),
                      style: AppTextStyles.titleMd.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Horizontal stepper — تم القبول ← استلمت من الكافيه ← تم التوصيل.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm16),
            child: DeliveryProgressBar(
              labels: [
                strings.stepAccepted,
                strings.stepPickedUp,
                strings.stepDelivered,
              ],
              completedCount: completedCount,
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 88),
        ],
      ),

      // Sticky bottom button advancing the next step; disabled while an
      // in-flight call runs so double-taps can't skip steps.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter16,
            AppSpacing.xs8,
            AppSpacing.gutter16,
            AppSpacing.xs8,
          ),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _busy || step == DriverStep.delivered ? null : _advance,
            icon: Icon(switch (step) {
              null => Icons.check_circle_outline,
              DriverStep.accepted => Icons.takeout_dining_outlined,
              DriverStep.pickedUp => Icons.celebration_outlined,
              DriverStep.delivered => Icons.done_all_outlined,
            }, size: 22),
            label: Text(buttonLabel),
          ),
        ),
      ),
    );
  }

  String _customerNameFor(String? phone) {
    final fromMap = phone == null ? null : _customerNames[phone];
    if (fromMap != null && fromMap.trim().isNotEmpty) return fromMap;
    return phone ?? '—';
  }
}

// ---------------------------------------------------------------------------
// Full-screen panels — same permission-lock pattern as the staff board
// ---------------------------------------------------------------------------

/// قفل 🔒 بلا صلاحية سائق — profiles.role not elevated; points at the SQL.
class _LockPanel extends StatelessWidget {
  const _LockPanel({required this.strings, required this.onRetry});

  final DriverStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 56,
              color: AppColors.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppSpacing.sm16),
            Text(
              strings.lockTitle,
              style: AppTextStyles.titleMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs8),
            Text(
              strings.lockHint,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(strings.retryCta),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryPanel extends StatelessWidget {
  const _RetryPanel({required this.strings, required this.onRetry});

  final DriverStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.wifi_off_outlined,
            size: 48,
            color: AppColors.outline,
          ),
          const SizedBox(height: AppSpacing.sm16),
          Text(strings.loadFailed, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm16),
          FilledButton(onPressed: onRetry, child: Text(strings.retryCta)),
        ],
      ),
    );
  }
}
