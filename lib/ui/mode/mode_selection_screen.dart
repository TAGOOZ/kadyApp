// Mode selection (issue #003 / FEATURES §3.3): three big service-mode cards.
// Selection is stored in the shared checkout draft, then /checkout opens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_checkout.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/orders_repository.dart';

class ModeSelectionScreen extends ConsumerWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = CheckoutStringsCatalog.of(lang);

    return Scaffold(
      appBar: AppBar(title: Text(strings.modeSelectionTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter16),
          children: [
            _ModeCard(
              icon: Icons.table_restaurant_outlined,
              title: strings.modeDineIn,
              helper: strings.modeDineInHelper,
              onTap: () => _select(context, ref, OrderMode.dineIn),
            ),
            const SizedBox(height: AppSpacing.sm16),
            _ModeCard(
              icon: Icons.shopping_bag_outlined,
              title: strings.modePickup,
              helper: strings.modePickupHelper,
              onTap: () => _select(context, ref, OrderMode.pickup),
            ),
            const SizedBox(height: AppSpacing.sm16),
            _ModeCard(
              icon: Icons.delivery_dining_outlined,
              title: strings.modeDelivery,
              helper: strings.modeDeliveryHelper,
              onTap: () => _select(context, ref, OrderMode.delivery),
            ),
          ],
        ),
      ),
    );
  }

  void _select(BuildContext context, WidgetRef ref, OrderMode mode) {
    ref.read(checkoutDraftProvider.notifier).setMode(mode);
    context.push('/checkout');
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.helper,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String helper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.margin20),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.parchment,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 30, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.titleMd),
                    const SizedBox(height: 4),
                    Text(
                      helper,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
