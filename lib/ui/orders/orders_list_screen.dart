// Customer orders list (#006): active orders on top (newest first) with a
// سجل section below, fed live by Supabase Realtime filtered on
// google_user_id (ADR-0006). Tapping a card opens its timeline.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_checkout.dart';
import '../../core/l10n/strings_orders.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/auth_controller.dart';
import '../../domain/order_status_flow.dart';
import '../../data/repos/order_status_repository.dart';

class OrdersListScreen extends ConsumerWidget {
  const OrdersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = OrdersStringsCatalog.of(lang);
    final googleUserId = ref.watch(authControllerProvider).googleUser?.id;

    if (googleUserId == null || googleUserId.isEmpty) {
      // Guests have local-only progress; there is nothing to list yet.
      return Scaffold(
        appBar: AppBar(title: Text(strings.ordersTitle)),
        body: _EmptyState(strings: strings),
      );
    }

    final ordersAsync = ref.watch(ownOrdersStreamProvider(googleUserId));
    return Scaffold(
      appBar: AppBar(title: Text(strings.ordersTitle)),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Standard error policy: banner + retry resubscribes the stream.
        error: (_, _) => _RetryBanner(
          message: strings.loadFailed,
          cta: strings.retryCta,
          onRetry: () =>
              ref.invalidate(ownOrdersStreamProvider(googleUserId)),
        ),
        data: (orders) {
          if (orders.isEmpty) return _EmptyState(strings: strings);

          final active = [
            ...orders.where((order) => !order.isCompleted),
          ]..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
          final history = [
            ...orders.where((order) => order.isCompleted),
          ]..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.gutter16),
            children: [
              if (active.isNotEmpty) ...[
                _SectionHeader(label: strings.activeSection),
                for (final order in active)
                  _OrderCard(order: order, strings: strings, lang: lang),
              ],
              if (history.isNotEmpty) ...[
                _SectionHeader(label: strings.historySection),
                for (final order in history)
                  _OrderCard(order: order, strings: strings, lang: lang),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.strings});

  final OrdersStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 56, color: AppColors.outline),
          const SizedBox(height: AppSpacing.sm16),
          Text(strings.emptyTitle, style: AppTextStyles.titleMd),
          const SizedBox(height: AppSpacing.sm16),
          FilledButton(
            onPressed: () => context.go('/mode-selection'),
            child: Text(strings.emptyCta),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs8, bottom: AppSpacing.xs8),
      child: Text(label, style: AppTextStyles.titleMd),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.strings,
    required this.lang,
  });

  final CustomerOrder order;
  final OrdersStrings strings;
  final AppLang lang;

  String get _modeLabel => switch (order.modeWire) {
        'dine_in' =>
          CheckoutStringsCatalog.of(lang).modeDineIn,
        'delivery' =>
          CheckoutStringsCatalog.of(lang).modeDelivery,
        _ =>
          CheckoutStringsCatalog.of(lang).modePickup,
      };

  String get _statusLabel {
    if (order.status == OrderWireStatus.cancelled) {
      return strings.cancelledChip;
    }
    final mode = order.flowMode;
    if (mode != null) {
      final step = OrderStatusFlow.stepFor(mode, order.status);
      if (step != null) return step.labelAr;
    }
    // `done` sits outside the pickup flow — handoff already happened.
    return strings.donePickupChip;
  }

  Color get _statusColor =>
      order.status == OrderWireStatus.cancelled ? AppColors.error : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.mdLg12),
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.parchment,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '#${order.displayNumber}',
                      style: AppTextStyles.labelMd.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.coffeeBean,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      labelPadding: EdgeInsets.zero,
                      label: Text(
                        _modeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelMd,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      order.totalEgp == null
                          ? ''
                          : '${order.totalEgp} '
                              '${CheckoutStringsCatalog.of(lang).currencySuffix}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppTextStyles.bodyLg
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.itemsCount(order.itemCount),
                      style: AppTextStyles.bodySm.copyWith(
                         color: AppColors.textMuted,
                       ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      _statusLabel,
                      style: AppTextStyles.labelMd.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetryBanner extends StatelessWidget {
  const _RetryBanner({
    required this.message,
    required this.cta,
    required this.onRetry,
  });

  final String message;
  final String cta;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_outlined, color: AppColors.outline),
          const SizedBox(height: AppSpacing.xs8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm16),
          FilledButton.tonal(onPressed: onRetry, child: Text(cta)),
        ],
      ),
    );
  }
}
