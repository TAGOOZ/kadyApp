// 10-slot stamp card (#005): ☕ per stamped visit, caption with the
// free-snack reward, badge for fully-earned cards awaiting redemption.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';

class StampCardWidget extends StatelessWidget {
  const StampCardWidget({
    super.key,
    required this.stamps,
    required this.completedCards,
    required this.strings,
  });

  final int stamps;
  final int completedCards;
  final HomeStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm16),
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        boxShadow: AppShadows.coffeeShadows(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.stampCaption(stamps),
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.outline,
                  ),
                ),
              ),
              if (completedCards > 0)
                Container(
                  key: const Key('home_completed_cards_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs8,
                    vertical: 2,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.secondaryContainer,
                    borderRadius:
                        BorderRadius.all(Radius.circular(AppRadii.pill)),
                  ),
                  child: Text(
                    strings.completedCardsBadge(completedCards),
                    style: AppTextStyles.labelMd
                        .copyWith(color: AppColors.coffeeBean),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs8 + 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(10, (index) {
              final filled = index < stamps;
              return Tooltip(
                message: '${index + 1}',
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppColors.primary : AppColors.parchment,
                    border: Border.all(
                      color: filled
                          ? AppColors.primary
                          : AppColors.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: filled
                      ? const Text('☕', style: TextStyle(fontSize: 14))
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
