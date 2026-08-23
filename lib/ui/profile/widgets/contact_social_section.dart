import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_profile.dart';
import '../../../core/theme/app_theme.dart';

class ContactSocialSection extends StatelessWidget {
  const ContactSocialSection({super.key, required this.lang});

  final AppLang lang;

  static const _facebookUrl = 'https://www.facebook.com/elkadycafe1/';
  static const _instagramUrl = 'https://www.instagram.com/elkadycafee';
  static const _tiktokUrl = 'https://www.tiktok.com/@elkady.cafe';
  static const _phoneUri = 'tel:+20452508799';
  static const _whatsAppNumber = '201206268500';
  static const _whatsAppUrl = 'https://wa.me/201206268500';

  Future<void> _open(
    BuildContext context, {
    required String fallbackUrl,
    List<String> nativeSchemes = const [],
  }) async {
    for (final scheme in nativeSchemes) {
      final uri = Uri.tryParse(scheme);
      if (uri == null) continue;
      try {
        if (await canLaunchUrl(uri)) {
          final launched =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) return;
        }
      } catch (_) {}
    }
    final fallback = Uri.parse(fallbackUrl);
    try {
      final launched =
          await launchUrl(fallback, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ProfileStringsCatalog.of(lang).comingSoon)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ProfileStringsCatalog.of(lang).comingSoon)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProfileStringsCatalog.of(lang);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm16),
      padding: const EdgeInsets.all(AppSpacing.sm16),
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        boxShadow: AppShadows.coffeeShadows(
          offset: const Offset(0, 4),
          blurRadius: 14,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.contactSectionTitle, style: AppTextStyles.titleSm),
          const SizedBox(height: AppSpacing.xs8 / 2),
          Text(
            s.contactSectionSubtitle,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SocialButton(
                key: const Key('social_facebook'),
                label: s.socialFacebook,
                background: AppColors.facebook,
                icon: Icons.facebook,
                onTap: () => _open(
                  context,
                  fallbackUrl: _facebookUrl,
                  nativeSchemes: const [
                    'fb://page/61576087318167',
                    'fb://page/elkadycafe1',
                    'fb://facewebmodal/f?href=https://www.facebook.com/elkadycafe1/',
                  ],
                ),
              ),
              _SocialButton(
                key: const Key('social_instagram'),
                label: s.socialInstagram,
                background: AppColors.instagram,
                icon: Icons.camera_alt_rounded,
                onTap: () => _open(
                  context,
                  fallbackUrl: _instagramUrl,
                  nativeSchemes: const [
                    'instagram://user?username=elkadycafee',
                  ],
                ),
              ),
              _SocialButton(
                key: const Key('social_tiktok'),
                label: s.socialTiktok,
                background: AppColors.tiktok,
                icon: Icons.music_note_rounded,
                onTap: () => _open(
                  context,
                  fallbackUrl: _tiktokUrl,
                  nativeSchemes: const [
                    'tiktok://user?username=elkady.cafe',
                    'snssdk1233://user/profile/elkady.cafe',
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm16),
          const Divider(),
          const SizedBox(height: AppSpacing.xs8),
          _ContactRow(
            key: const Key('contact_phone'),
            icon: Icons.phone_rounded,
            iconColor: AppColors.primary,
            label: s.contactPhoneLabel,
            value: s.contactPhoneNumber,
            onTap: () => _open(
              context,
              fallbackUrl: _phoneUri,
              nativeSchemes: const [_phoneUri],
            ),
          ),
          const SizedBox(height: AppSpacing.xs8),
          _ContactRow(
            key: const Key('contact_whatsapp'),
            icon: Icons.chat_rounded,
            iconColor: AppColors.whatsapp,
            label: s.contactWhatsAppLabel,
            value: s.contactWhatsAppNumber,
            onTap: () => _open(
              context,
              fallbackUrl: _whatsAppUrl,
              nativeSchemes: const [
                'whatsapp://send?phone=$_whatsAppNumber',
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.sm16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    value,
                    style: AppTextStyles.bodyLg.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.coffeeBean,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    super.key,
    required this.label,
    required this.background,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color background;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md8),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                boxShadow: AppShadows.coffeeShadows(
                  offset: const Offset(0, 4),
                  blurRadius: 10,
                ),
              ),
              child: Icon(icon, color: AppColors.paperWhite, size: 28),
            ),
            const SizedBox(height: AppSpacing.xs8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelMd.copyWith(color: AppColors.coffeeBean),
            ),
          ],
        ),
      ),
    );
  }
}
