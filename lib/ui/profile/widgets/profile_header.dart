// Profile header (#011): avatar initial circle + camera badge (image_picker
// → Supabase Storage `avatars` bucket, Western digits, RTL-first).
// Gold tier gets a gradient border per the Stitch design ref.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_profile.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/loyalty_controller.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    required this.tier,
    required this.strings,
    required this.onCameraTap,
    this.isGuest = false,
    this.avatarUrl,
  });

  final String name;
  final Tier tier;
  final ProfileStrings strings;
  final VoidCallback onCameraTap;
  final bool isGuest;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.screenTitle,
          style: AppTextStyles.headlineMobile.copyWith(
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm16),
        Row(
          children: [
            GestureDetector(
              onTap: onCameraTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppColors.parchment, AppColors.primaryFixedTint],
                      ),
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: avatarUrl != null && avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: avatarUrl!,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Text(
                              name.isEmpty ? '؟' : name.characters.first.toUpperCase(),
                              style: AppTextStyles.headlineMobile
                                  .copyWith(color: AppColors.primary),
                            ),
                            errorWidget: (_, _, _) => Text(
                              name.isEmpty ? '؟' : name.characters.first.toUpperCase(),
                              style: AppTextStyles.headlineMobile
                                  .copyWith(color: AppColors.primary),
                            ),
                          )
                        : Text(
                            name.isEmpty ? '؟' : name.characters.first.toUpperCase(),
                            style: AppTextStyles.headlineMobile
                                .copyWith(color: AppColors.primary),
                          ),
                  ),
                  PositionedDirectional(
                    end: -2,
                    bottom: -2,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    name,
                    style: AppTextStyles.titleMd,
                  ),
                  if (!isGuest) ...[
                    const SizedBox(height: 6),
                    _TierChip(tier: tier, label: strings.tierLabel(tier)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({required this.tier, required this.label});

  final Tier tier;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (Gradient? border, Color fill, Color foreground) = switch (tier) {
      // Gold: warm gradient border per design ref.
      Tier.gold => (
          const LinearGradient(colors: [Color(0xFFF6D365), Color(0xFFB8860B)]),
          AppColors.paperWhite,
          const Color(0xFF8A6200),
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
      padding: border == null
          ? EdgeInsets.zero
          : const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        gradient: border,
        color: border == null ? fill : null,
        borderRadius:
            const BorderRadius.all(Radius.circular(AppRadii.pill)),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: border == null ? 10 : 8.5,
          vertical: border == null ? 3 : 1.5,
        ),
        decoration: border == null
            ? null
            : const BoxDecoration(
                color: AppColors.paperWhite,
                borderRadius: BorderRadius.all(Radius.circular(AppRadii.pill)),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tier == Tier.gold ? Icons.star_rounded : Icons.verified_rounded,
              size: 14,
              color: foreground,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: AppTextStyles.labelMd.copyWith(
                 fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
