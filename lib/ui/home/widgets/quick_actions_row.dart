// Four quick-action tiles (#005): order now, scan & earn (role-aware),
// games hub, rewards/profile. Scan & earn is wired role-aware in
// HomeScreen (FEATURES §3.2/§6) — staff → /staff/lookup (QR + phone
// fallback); customer shows comingSoon SnackBar until the customer scanner
// screen lands. See HomeScreen onComingSoon for the role guard.
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
    return Row(
      children: [
        _Tile(
          icon: Icons.local_cafe_outlined,
          label: strings.actionOrderNow,
          // Order flow is outside StatefulShell — push preserves Home in the
          // stack (consistent with ActiveOrderStrip's push('/orders')). For
          // shell tabs (/games, /profile) push also keeps Home reachable via
          // back; StatefulShell's goBranch would replace the branch instead.
          // push is intentional here (see router.dart StatefulShellRoute).
          onTap: () => context.push('/mode-selection'),
        ),
        _Tile(
          icon: Icons.qr_code_scanner,
          label: strings.actionScanEarn,
          onTap: onComingSoon,
        ),
        _Tile(
          icon: Icons.videogame_asset_outlined,
          label: strings.actionPlay,
          onTap: () => context.push('/games'),
        ),
        _Tile(
          icon: Icons.card_giftcard,
          label: strings.actionRewards,
          onTap: () => context.push('/profile'),
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
    return Expanded(
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs8 + 4),
          decoration: BoxDecoration(
            color: AppColors.paperWhite,
            borderRadius:
                const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
            boxShadow: AppShadows.coffeeShadows(offset: const Offset(0, 4)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 26, color: AppColors.secondary),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.coffeeBean,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
