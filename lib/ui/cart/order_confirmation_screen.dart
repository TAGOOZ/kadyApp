// Order confirmation (issue #003): green check, DB display number chip,
// mode badge + ETA, items summary, totals, points banner and cash payment
// line. Tracking (#006) resolves the order uuid from its display number
// and lands on /orders/:id.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_checkout.dart';
import '../../core/l10n/strings_home.dart';
import '../../core/l10n/strings_orders.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/orders_repository.dart';
import '../../data/repos/order_status_repository.dart';
import '../../domain/auth_controller.dart';
import '../../domain/cart_controller.dart';
import '../../domain/loyalty_controller.dart';

class OrderConfirmationScreen extends ConsumerWidget {
  const OrderConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = CheckoutStringsCatalog.of(lang);
    final ordersStrings = OrdersStringsCatalog.of(lang);
    final homeStrings = HomeStringsCatalog.of(lang);
    ref.listen<int>(loyaltyProvider.select((s) => s.spinnerTokens), (prev, next) {
      if (prev != null && next > prev && context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('${homeStrings.tokenEarnedTitle} ${homeStrings.tokenEarnedBody}'),
            action: SnackBarAction(label: homeStrings.actionPlay, onPressed: () => context.push('/games/spinner')),
          ));
      }
    });
    final args = GoRouterState.of(context).extra;
    if (args is! ConfirmationArgs) {
      // Direct deep-link without a placed order — nothing to show.
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(strings.emptyTitle)),
      );
    }

    // ConfirmationArgs carries only the display number; resolve the uuid
    // from the customer's own orders so tracking deep-links correctly.
    final googleUserId = ref.watch(authControllerProvider).googleUser?.id;
    final ownOrders =
        googleUserId == null ? null : ref.watch(ownOrdersOnceProvider(googleUserId)).value;
    final trackedOrderId = ownOrders
        ?.where((order) => order.displayNumber == args.displayNumber)
        .map((order) => order.id)
        .firstOrNull;

    final modeName = switch (args.mode) {
      OrderMode.dineIn => strings.modeDineIn,
      OrderMode.pickup => strings.modePickup,
      OrderMode.delivery => strings.modeDelivery,
    };
    // "~10 دقائق استلام" / "~10 دقائق صالة" · "~30 دقيقة توصيل".
    final etaBase =
        args.mode == OrderMode.delivery ? strings.etaDelivery : strings.etaPickup;
    final eta = '$etaBase · $modeName';
    final paymentLine = args.mode == OrderMode.delivery
        ? strings.paymentCashOnDelivery
        : strings.paymentCashHere;

    return Scaffold(
      appBar: AppBar(title: Text(strings.checkoutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.gutter16),
        children: [
          const SizedBox(height: AppSpacing.sm16),
          Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(
                color: AppColors.successContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.check_rounded,
                  size: 64, color: AppColors.success),
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          Center(
            child: Text(
              strings.confirmedTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMobile,
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.xs8,
            runSpacing: AppSpacing.xs8,
            children: [
              Chip(
                label: Text(
                  strings.orderChip(args.displayNumber),
                  style: AppTextStyles.labelMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Chip(label: Text(modeName)),
              Chip(label: Text(eta)),
            ],
          ),
          const SizedBox(height: AppSpacing.md24),
          Text(strings.itemsSummaryTitle, style: AppTextStyles.titleMd),
          const SizedBox(height: AppSpacing.xs8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in args.items)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: AppSpacing.xs8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.nameAr} × ${item.qty}',
                              style: AppTextStyles.bodySm,
                            ),
                          ),
                          Text(
                            strings.egp(item.unitTotalEgp * item.qty),
                            style: AppTextStyles.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  _Row(
                    label: strings.subtotalRow,
                    value: strings.egp(args.subtotalEgp),
                  ),
                  if (args.mode == OrderMode.delivery)
                    _Row(
                      label: strings.deliveryFeeRow,
                      value: strings.egp(args.deliveryFeeEgp),
                    ),
                  _Row(
                    label: strings.totalRow,
                    value: strings.egp(args.totalEgp),
                    emphasized: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm16),
            decoration: BoxDecoration(
              color: AppColors.parchment,
              borderRadius: BorderRadius.circular(AppRadii.md8),
            ),
            child: Row(
              children: [
                const Text('☕', style: TextStyle(fontSize: 22)),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(
                  child: Text(
                    strings.pointsBanner(args.pointsPreview),
                    style: AppTextStyles.bodySm
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm16),
          Row(
            children: [
              const Icon(Icons.payments_outlined, size: 20),
              const SizedBox(width: AppSpacing.xs8),
              Expanded(child: Text(paymentLine, style: AppTextStyles.bodySm)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg32),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.margin20,
            AppSpacing.sm16,
            AppSpacing.margin20,
            AppSpacing.md24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () {
                  final orderId = trackedOrderId;
                  if (orderId != null) {
                    context.push('/orders/$orderId');
                  } else {
                    // Order not resolvable yet (offline/guest edge) —
                    // standard error policy keeps the user informed.
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ordersStrings.trackOrderTooltip)),
                    );
                  }
                },
                child: Text(strings.trackCta),
              ),
              const SizedBox(height: AppSpacing.xs8),
              TextButton(
                onPressed: () => _goHome(context, ref),
                child: Text(strings.backHomeCta),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goHome(BuildContext context, WidgetRef ref) {
    // CartController has no bulk clear; removing every line empties it.
    for (final line in ref.read(cartProvider)) {
      ref.read(cartProvider.notifier).removeLine(line);
    }
    ref.read(checkoutDraftProvider.notifier).reset();
    context.go('/home');
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? AppTextStyles.titleSm
        : AppTextStyles.bodyLg;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
