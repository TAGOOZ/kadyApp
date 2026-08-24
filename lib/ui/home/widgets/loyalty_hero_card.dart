// Loyalty hero card (#005 v2): points + stamps merged into ONE surface —
// mirrors the Starbucks rewards-tracker pattern (single expandable balance
// card instead of two competing white cards). Guest mode renders zeros with
// the register link. All crediting stays server-authoritative (FEATURES §4).
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/guest_save_prompt.dart';

const int kNextRewardGoal = 200;

class LoyaltyHeroCard extends StatelessWidget {
  const LoyaltyHeroCard({
    super.key,
    required this.points,
    required this.stamps,
    required this.completedCards,
    required this.strings,
    this.signedIn = true,
  });

  final int points;
  final int stamps;
  final int completedCards;
  final HomeStrings strings;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm16),
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius:
            const BorderRadius.all(Radius.circular(AppRadii.lg16)),
        boxShadow: AppShadows.coffeeShadows(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: AppColors.primaryFixedTint,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.emoji_events_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs8),
              Text(
                strings.rewardsSectionTitle,
                style: AppTextStyles.titleSm.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs8 + 2),
          // -- Points row -------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$points',
                style: AppTextStyles.headlineMobile.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                strings.pointsSuffix,
                style:
                    AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  strings.pointsProgress(points, kNextRewardGoal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs8),
          ClipRRect(
            borderRadius:
                const BorderRadius.all(Radius.circular(AppRadii.pill)),
            child: LinearProgressIndicator(
              value: (points / kNextRewardGoal).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: AppColors.parchment,
              valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
            ),
          ),
          const SizedBox(height: AppSpacing.xs8),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.freeDrinkCaption,
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textMuted),
                ),
              ),
              if (!signedIn)
                TextButton(
                  key: const Key('home_guest_register'),
                  onPressed: () => showGuestSavePrompt(context, points: points),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    strings.registerLink,
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          Divider(color: AppColors.outline.withValues(alpha: 0.25)),
          // -- Stamps row -------------------------------------------------
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.stampCaption(stamps),
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.textMuted,
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
