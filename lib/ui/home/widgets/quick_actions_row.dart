// Quick actions — 2×2 grid (#005 v2): scan & earn (role-aware), games,
// my orders, rewards. "Order now" moved OUT of the tiles into the hero CTA
// above (one primary action per screen); the grid holds secondary paths.
// Scan & earn stays role-aware in HomeScreen (FEATURES §3.2/§6): staff →
// /staff/lookup; customer opens QrScannerSheet + parseQrPhone (mobile_scanner).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings_home.dart';
import '../../../core/theme/app_theme.dart';

class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({
    super.key,
    required this.strings,
    required this.onComingSoon,
  });

  final HomeStrings strings;
  final VoidCallback onComingSoon;

  @override
  Widget build(BuildContext context) {
    // push() keeps Home reachable via back (consistent with the rest of the
    // hub — see router.dart StatefulShellRoute note in git history).
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Tile(
                icon: Icons.qr_code_scanner,
                label: strings.actionScanEarn,
                onTap: onComingSoon,
              ),
            ),
            const SizedBox(width: AppSpacing.xs8 + 4),
            Expanded(
              child: _Tile(
                icon: Icons.videogame_asset_outlined,
                label: strings.actionPlay,
                onTap: () => context.push('/games'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs8 + 4),
        Row(
          children: [
            Expanded(
              child: _Tile(
                icon: Icons.card_giftcard,
                label: strings.actionRewards,
                onTap: () => context.push('/profile'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs8 + 4),
            Expanded(
              child: _Tile(
                icon: Icons.receipt_long_outlined,
                label: strings.actionMyOrders,
                onTap: () => context.push('/orders'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm16),
        decoration: BoxDecoration(
          color: AppColors.paperWhite,
          borderRadius:
              const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
          boxShadow: AppShadows.coffeeShadows(offset: const Offset(0, 4)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primaryFixedTint,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.coffeeBean,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
