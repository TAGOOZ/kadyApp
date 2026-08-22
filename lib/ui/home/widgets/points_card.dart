// Points widget card (#005): current points + progress toward the next
// 200-pt free-drink reward. Tapping opens a DEV debug sheet wired to
// `applyDemoBoost` until real crediting lands (#007/#008).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/loyalty_controller.dart';
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

  void _openDevSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _DevBoostSheet(strings: strings),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
      onTap:
          signedIn ? () => _openDevSheet(context, ref) : null,
      child: Container(
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
                if (signedIn)
                  TextButton(
                    key: const Key('home_dev_boost_open'),
                    onPressed: () => _openDevSheet(context, ref),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: AppTextStyles.labelMd,
                    ),
                    child: Text(
                      strings.devBoostCardLabel,
                      style: AppTextStyles.labelMd
                          .copyWith(color: AppColors.outline),
                    ),
                  )
                else
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
      ),
    );
  }
}

class _DevBoostSheet extends ConsumerWidget {
  const _DevBoostSheet({required this.strings});

  final HomeStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
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
            Text(
              strings.devBoostSheetTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMd.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.sm16),
            FilledButton(
              key: const Key('home_dev_boost_apply'),
              onPressed: () async {
                await ref.read(loyaltyProvider.notifier).applyDemoBoost();
                if (!context.mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(strings.devBoostApplied)),
                );
              },
              child: Text(strings.devBoostApplyLabel),
            ),
          ],
        ),
      ),
    );
  }
}
