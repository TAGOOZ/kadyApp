// Games hub tab (#005 shell) — routes into each game screen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_games.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/loyalty_controller.dart';

class GamesHubScreen extends ConsumerWidget {
  const GamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final s = GamesStrings.of(lang);
    final loyalty = ref.watch(loyaltyProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.hubTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.margin20),
        children: [
          Text(s.hubSubtitle, style: AppTextStyles.bodySm.copyWith(color: AppColors.outline)),
          const SizedBox(height: AppSpacing.sm16),
          _GameTile(
            icon: Icons.casino_outlined,
            title: s.spinnerTitle,
            lockedHint: s.spinnerLockedHint,
            tokens: loyalty.spinnerTokens,
            route: '/games/spinner',
          ),
          _GameTile(
            icon: Icons.style_outlined,
            title: s.matchTitle,
            lockedHint: s.matchLockedHint,
            tokens: loyalty.matchTokens,
            route: '/games/match',
          ),
          _GameTile(
            icon: Icons.confirmation_number_outlined,
            title: s.scratchTitle,
            lockedHint: s.scratchLockedHint,
            tokens: loyalty.scratchTokens,
            route: '/games/scratch',
          ),
          _GameTile(
            icon: Icons.emoji_events_outlined,
            title: s.questsTitle,
            lockedHint: s.questsHint,
            tokens: null,
            route: '/games/quests',
          ),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.icon,
    required this.title,
    required this.lockedHint,
    required this.tokens,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String lockedHint;
  final int? tokens;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.paperWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        side: BorderSide(color: AppColors.parchment),
      ),
      child: ListTile(
        leading: Icon(icon, size: 32, color: AppColors.primary),
        title: Text(title, style: AppTextStyles.titleMd),
        subtitle: Text(
          tokens == null || tokens! > 0
              ? (tokens != null ? '$tokens ×' : lockedHint)
              : lockedHint,
          style: AppTextStyles.bodySm.copyWith(color: AppColors.secondary),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(route),
      ),
    );
  }
}
