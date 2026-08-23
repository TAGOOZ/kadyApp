// One customer profile card on the lookup screen (#013, FEATURES §6.4):
// avatar initial + name/phone + tier chip (derived from loyalty lifetime
// points — read-only reuse of loyalty_controller), stats grid النقاط /
// الأختام x من 10 / الزيارات, a mini recent-orders list and the actions row
// (إضافة مكافأة / تسجيل زيارة). The overflow icon opens the per-phone
// activity log sheet. All actions are delegated to callbacks so tests record
// calls on a fake repo.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_lookup.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/customer_lookup_repository.dart';
import '../../../domain/loyalty_controller.dart';

class CustomerResultCard extends StatelessWidget {
  const CustomerResultCard({
    super.key,
    required this.profile,
    required this.strings,
    required this.onAddReward,
    required this.onRegisterVisit,
    required this.onOpenActivityLog,
  });

  final CustomerProfile profile;
  final LookupStrings strings;
  final VoidCallback onAddReward;
  final VoidCallback onRegisterVisit;
  final VoidCallback onOpenActivityLog;

  String get _tierLabel => switch (derivedTier(profile.lifetimePoints)) {
        Tier.gold => strings.tierGold,
        Tier.silver => strings.tierSilver,
        Tier.bronze => strings.tierBronze,
      };

  @override
  Widget build(BuildContext context) {
    final initial = profile.name.trim().isEmpty
        ? '?'
        : profile.name.trim().characters.first.toUpperCase();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm16),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Identity row: avatar initial · name+phone · tier chip · overflow.
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primaryFixedTint,
                  child: Text(
                    initial,
                    style: AppTextStyles.titleMd
                        .copyWith(color: AppColors.coffeeBean),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name, style: AppTextStyles.titleMd),
                      Text(
                        profile.phone,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixedTint,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    _tierLabel,
                    style: AppTextStyles.labelMd.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: strings.activityLogTitle,
                  icon: const Icon(Icons.more_vert),
                  onPressed: onOpenActivityLog,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm16),
            // Stats grid: النقاط | الأختام x من 10 | الزيارات n.
            Row(
              children: [
                _Stat(value: '${profile.points}', label: strings.statsPoints),
                const _VerticalDivider(),
                _Stat(
                  value: strings.stampsOf(profile.stamps),
                  label: strings.statsStamps,
                ),
                const _VerticalDivider(),
                _Stat(value: '${profile.visits}', label: strings.statsVisits),
              ],
            ),
            const SizedBox(height: AppSpacing.sm16),
            Text(strings.recentOrdersTitle, style: AppTextStyles.bodySm),
            const SizedBox(height: 4),
            if (profile.recentOrders.isEmpty)
              Text(
                strings.recentOrdersEmpty,
                style:
                    AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
              )
            else
              for (final order in profile.recentOrders)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 16, color: AppColors.outline),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          formatLookupWhenUtc(order.createdAtUtc),
                          style: AppTextStyles.bodySm,
                        ),
                      ),
                      if (order.totalEgp != null)
                        Text(
                          strings.total(order.totalEgp!),
                          style: AppTextStyles.labelMd.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
            const SizedBox(height: AppSpacing.md24),
            // Actions row: filled green grant · outlined visit registration.
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAddReward,
                    icon: const Icon(Icons.card_giftcard_outlined, size: 18),
                    label: Text(strings.addRewardCta),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRegisterVisit,
                    icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                    label: Text(strings.registerVisitCta),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.outline.withValues(alpha: 0.25),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs8),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTextStyles.titleMd.copyWith(color: AppColors.primary),
          ),
          Text(
            label,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
