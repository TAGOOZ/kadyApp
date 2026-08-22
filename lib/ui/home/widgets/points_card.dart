// Points widget card (#005): current points + progress toward the next
// 200-pt free-drink reward. Real crediting flows from placed orders (#007).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/guest_save_prompt.dart';

const int kNextRewardGoal = 200;

class PointsCard extends ConsumerWidget {
  const PointsCard({
    super.key,
    required this.points,
    required this.strings,
    this.signedIn = true,
  });

  final int points;
  final HomeStrings strings;
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.outline),
                ),
                const Spacer(),
                Text(
                  strings.pointsProgress(points, kNextRewardGoal),
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.outline,
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
                        .copyWith(color: AppColors.outline),
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
        ],
      ),
    );
  }
}
