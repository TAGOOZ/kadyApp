// Greeting + avatar + tier chip (issue #005, FEATURES §3.2).
// Tier chip colors mirror the profile header treatment (gold gradient).
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/loyalty_controller.dart';

class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    required this.firstName,
    required this.tier,
    required this.strings,
    required this.onAvatarTap,
    this.isGuest = false,
  });

  final String firstName;
  final Tier tier;
  final HomeStrings strings;
  final VoidCallback onAvatarTap;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onAvatarTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.parchment, AppColors.primaryFixedTint],
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              isGuest || firstName.isEmpty
                  ? '؟'
                  : firstName.characters.first.toUpperCase(),
              style: AppTextStyles.titleMd.copyWith(color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs8),
        Expanded(
          child: Text(
            isGuest || firstName.isEmpty
                ? strings.greetingGeneric
                : strings.greeting(firstName),
            style: AppTextStyles.headlineMobile.copyWith(
              color: AppColors.primary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _TierChip(tier: tier, strings: strings),
      ],
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({required this.tier, required this.strings});

  final Tier tier;
  final HomeStrings strings;

  @override
  Widget build(BuildContext context) {
    final (Gradient? border, Color fill, Color foreground) = switch (tier) {
      // Gold: warm gradient border per design ref.
      Tier.gold => (
          const LinearGradient(colors: [Color(0xFFF6D365), Color(0xFFB8860B)]),
          AppColors.paperWhite,
          const Color(0xFF9C6F0A),
        ),
      Tier.silver => (
          null,
          const Color(0xFFECEFF1),
          const Color(0xFF546E7A),
        ),
      Tier.bronze => (
          null,
          const Color(0xFFF3E0D1),
          const Color(0xFF8D5524),
        ),
    };

    return Container(
      padding: border == null ? EdgeInsets.zero : const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        gradient: border,
        color: border == null ? fill : null,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs8 + 4,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: border == null ? fill : AppColors.paperWhite,
          borderRadius:
              const BorderRadius.all(Radius.circular(AppRadii.pill)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tier == Tier.gold ? Icons.star_rounded : Icons.verified_rounded,
              size: 14,
              color: foreground,
            ),
            const SizedBox(width: 4),
            Text(
              strings.tierLabel(tier),
              style: AppTextStyles.labelMd.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
