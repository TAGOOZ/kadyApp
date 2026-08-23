// Quests & badges screen (#010) — Stitch ref `9574eed6` layout:
// segmented tabs المهام / الشارات, quest cards (icon, linear progress,
// `٢/٣` label, deadline chip + date, reward chip, استلم المكافأة button)
// and a circular-medallion badge grid (gold/green earned, gray locked).
//
// Progress is recomputed every refresh from completed-order history via
// the pure engine (`quests_engine.dart`) fed by `questSnapshotProvider`.
// Claims persist through [QuestStateStore]; points credit through the
// shared loyalty seam (`grantPoints`), while match-token/stamp rewards
// queue as pending grants — the controller has no grant method for them
// yet (documented deviation, see PendingGrant).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_quests.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/quest_state_store.dart';
import '../../domain/auth_controller.dart';
import '../../domain/loyalty_controller.dart' show Tier, loyaltyProvider;
import '../../domain/quests_engine.dart';

class QuestsBadgesScreen extends ConsumerStatefulWidget {
  const QuestsBadgesScreen({super.key});

  @override
  ConsumerState<QuestsBadgesScreen> createState() => _QuestsBadgesScreenState();
}

class _QuestsBadgesScreenState extends ConsumerState<QuestsBadgesScreen> {
  int _tab = 0;
  Set<QuestId>? _claims;
  Map<BadgeId, DateTime> _badgesEarned = {};
  final Set<BadgeId> _celebratedThisSession = {};
  final Set<QuestId> _claiming = {};

  bool get _storeLoaded => _claims != null;

  @override
  void initState() {
    super.initState();
    _hydrateStore();
  }

  Future<void> _hydrateStore() async {
    final store = await ref.read(questStoreProvider.future);
    final phone = ref.read(authControllerProvider).phone ?? '';
    final claims = await store.claimedQuests(phone);
    final badges = await store.badgesEarned(phone);
    if (!mounted) return;
    setState(() {
      _claims = claims;
      _badgesEarned = badges;
    });
    // Badges may already be satisfiable by history fetched before the
    // store finished hydrating.
    _syncBadges();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Evaluates badge rules against the latest snapshot; persists newly
  /// earned badges and fires the one-time celebration banner.
  void _syncBadges() {
    final snapshot = ref.read(questSnapshotProvider).valueOrNull;
    if (!_storeLoaded || snapshot == null || !mounted) return;

    final loyalty = ref.read(loyaltyProvider);
    final s = QuestsStrings.of(lang);
    final earned = evaluateBadges(
      orders: snapshot.orders,
      windows: snapshot.windows,
      reachedGoldTier: loyalty.tier == Tier.gold,
    );

    var added = false;
    var celebrated = false;
    for (final id in earned) {
      if (_badgesEarned.containsKey(id)) continue;
      _badgesEarned[id] = DateTime.now().toUtc();
      added = true;
      if (_celebratedThisSession.add(id)) celebrated = true;
      _persistBadge(id);
    }
    if (!added) return;
    setState(() {});
    if (celebrated) _snack(s.newBadgeBanner);
  }

  // Fire-and-forget persistence — the local map is updated synchronously.
  Future<void> _persistBadge(BadgeId id) async {
    final store = await ref.read(questStoreProvider.future);
    final phone = ref.read(authControllerProvider).phone ?? '';
    await store.markBadgeEarned(phone, id);
  }

  AppLang get lang => ref.watch(localeNotifierProvider);

  Future<void> _claim(QuestDef def) async {
    final strings = QuestsStrings.of(lang);
    final progress = _progressOf(def.id);
    if (!progress.complete || !_storeLoaded) return;
    if (_claims!.contains(def.id)) return;
    if (!_claiming.add(def.id)) return; // reentrancy guard

    try {
      final store = await ref.read(questStoreProvider.future);
      final phone = ref.read(authControllerProvider).phone ?? '';

      switch (def.reward) {
        case QuestReward.bonusPoints:
          await ref.read(loyaltyProvider.notifier).grantPoints(50);
          if (!mounted) return;
          _snack(QuestsStrings.numerals(
            QuestsStrings.fill(strings.pointsClaimedTemplate, '50'),
            lang,
          ));
        case QuestReward.matchToken:
          try {
            await ref.read(loyaltyProvider.notifier).grantTokens(match: 1);
            if (!mounted) return;
            _snack(strings.tokenQueuedSnackbar);
          } catch (_) {
            await store.addPendingGrant(
              phone,
              PendingGrant(
                type: 'match_token',
                n: 1,
                createdAtUtc: DateTime.now().toUtc(),
              ),
            );
            if (!mounted) return;
            _snack(strings.tokenQueuedSnackbar);
          }
        case QuestReward.bonusStamp:
          try {
            await ref.read(loyaltyProvider.notifier).grantStamps(1);
            if (!mounted) return;
            _snack(strings.stampQueuedSnackbar);
          } catch (_) {
            await store.addPendingGrant(
              phone,
              PendingGrant(
                type: 'stamp',
                n: 1,
                createdAtUtc: DateTime.now().toUtc(),
              ),
            );
            if (!mounted) return;
            _snack(strings.stampQueuedSnackbar);
          }
      }

      final fresh = await store.markClaimed(phone, def.id);
      if (!fresh || !mounted) return; // double-tap guard
      setState(() => _claims = {..._claims!, def.id});
    } finally {
      _claiming.remove(def.id);
    }
  }

  QuestProgress _progressOf(QuestId id) {
    final snapshot = ref.read(questSnapshotProvider).valueOrNull;
    return evaluate(
      id,
      orders: snapshot?.orders ?? const [],
      itemCategories: snapshot?.itemCategories ?? const {},
      now: DateTime.now(),
    );
  }

  String _deadlineChipText(QuestDef def) {
    final now = DateTime.now();
    final dayMonth = def.endsThisWeek
        ? () {
            // Egypt week: Saturday → Friday (exclusive week end minus a day).
            final friday =
                weekEndInstantSaturday(now).subtract(const Duration(days: 1));
            return '${friday.day}/${friday.month}';
          }()
        : '${lastDayOfMonthOf(now)}/${now.month}';
    return QuestsStrings.numerals(dayMonth, lang);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final s = QuestsStrings.of(lang);

    // Badge evaluation runs whenever fresh order data lands…
    ref.listen(questSnapshotProvider, (_, next) {
      if (next.hasValue) _syncBadges();
    });
    // …and whenever loyalty changes (tier-crossing unlocks عميل ذهبي live).
    ref.listen(loyaltyProvider, (_, _) => _syncBadges());

    return Scaffold(
      appBar: AppBar(title: Text(s.screenTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.margin20),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(s.tabQuests)),
                ButtonSegment(value: 1, label: Text(s.tabBadges)),
              ],
              selected: {_tab},
              onSelectionChanged: (selection) =>
                  setState(() => _tab = selection.first),
            ),
          ),
          Expanded(
            child: _tab == 0 ? _buildQuestsTab(s, lang) : _buildBadgesTab(s, lang),
          ),
        ],
      ),
    );
  }

  // -- Quests tab ------------------------------------------------------------

  Widget _buildQuestsTab(QuestsStrings s, AppLang lang) {
    final snapshotAsync = ref.watch(questSnapshotProvider);

    Widget body;
    body = snapshotAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // Offline policy (#010 spec): failed fetch still renders the cards
      // at ٠/٣ with a retry banner; pull-to-refresh retries.
      error: (_, _) => _QuestList(
        s: s,
        offlineBanner: _OfflineRetryBanner(
          message: s.loadFailed,
          cta: s.retryCta,
          onRetry: () => ref.invalidate(questSnapshotProvider),
        ),
        children: [
          for (final def in questCatalog)
            QuestCard(
              def: def,
              progress: QuestProgress(progress: 0, target: def.target),
              claimed: false,
              claimEnabled: false,
              deadlineChipText: _deadlineChipText(def),
              s: s,
              lang: lang,
              onClaim: null,
            ),
        ],
      ),
      data: (snapshot) => _QuestList(
        s: s,
        offlineBanner: snapshot.offline
            ? _OfflineRetryBanner(
                message: s.loadFailed,
                cta: s.retryCta,
                onRetry: () => ref.invalidate(questSnapshotProvider),
              )
            : null,
        children: [
          for (final def in questCatalog)
            QuestCard(
              def: def,
              progress: _progressOf(def.id),
              claimed: _claims?.contains(def.id) ?? false,
              claimEnabled: _storeLoaded,
              deadlineChipText: _deadlineChipText(def),
              s: s,
              lang: lang,
              onClaim: () => _claim(def),
            ),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(questSnapshotProvider.future),
      child: body,
    );
  }

  // -- Badges tab ------------------------------------------------------------

  Widget _buildBadgesTab(QuestsStrings s, AppLang lang) {
    final defs = {
      BadgeId.matchNightsClub: Icons.sports_soccer_outlined,
      BadgeId.examWarrior: Icons.school_outlined,
      BadgeId.ramadanOwl: Icons.nightlight_round,
      BadgeId.goldLoyalist: Icons.workspace_premium_outlined,
    };
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(questSnapshotProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.margin20),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm16,
            crossAxisSpacing: AppSpacing.sm16,
            childAspectRatio: 0.95,
            children: [
              for (final entry in defs.entries)
                BadgeMedallion(
                  icon: entry.value,
                  title: s.badgeTitle(entry.key.name, lang),
                  earnedAt: _badgesEarned[entry.key],
                  gold: entry.key == BadgeId.goldLoyalist,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm16),
          _BottomBanner(label: s.bottomBanner),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _QuestList extends StatelessWidget {
  const _QuestList({
    required this.s,
    required this.children,
    this.offlineBanner,
  });

  final QuestsStrings s;
  final List<Widget> children;
  final Widget? offlineBanner;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.margin20),
      children: [
        if (offlineBanner != null) ...[offlineBanner!, const SizedBox(height: AppSpacing.sm16)],
        ...children,
        const SizedBox(height: AppSpacing.sm16),
        _BottomBanner(label: s.bottomBanner),
      ],
    );
  }
}

IconData _questIcon(QuestId id) => switch (id) {
      QuestId.drinksVariety => Icons.local_cafe_outlined,
      QuestId.matchNight => Icons.sports_soccer_outlined,
      QuestId.bothModes => Icons.local_shipping_outlined,
    };

class QuestCard extends StatelessWidget {
  const QuestCard({
    super.key,
    required this.def,
    required this.progress,
    required this.claimed,
    required this.claimEnabled,
    required this.deadlineChipText,
    required this.s,
    required this.lang,
    required this.onClaim,
  });

  final QuestDef def;
  final QuestProgress progress;
  final bool claimed;
  final bool claimEnabled;
  final String deadlineChipText;
  final QuestsStrings s;
  final AppLang lang;
  final VoidCallback? onClaim;

  String get _rewardLabel => switch (def.reward) {
        QuestReward.bonusPoints => QuestsStrings.fill(s.rewardPointsTemplate, '50'),
        QuestReward.matchToken => s.rewardMatchToken,
        QuestReward.bonusStamp => s.rewardBonusStamp,
      };

  @override
  Widget build(BuildContext context) {
    final clamped = progress.target <= 0
        ? 0.0
        : (progress.progress / progress.target).clamp(0.0, 1.0);
    final canClaim =
        claimEnabled && progress.complete && !claimed && onClaim != null;

    return Card(
      color: AppColors.paperWhite,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm16),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        side: BorderSide(color: AppColors.parchment),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.parchment,
                    borderRadius: BorderRadius.circular(AppRadii.mdLg12),
                  ),
                  child: Icon(_questIcon(def.id), color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(
                  child: Text(
                    lang == AppLang.ar ? def.titleAr : def.titleEn,
                    style: AppTextStyles.titleMd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs8),
            LinearProgressIndicator(
              value: clamped,
              minHeight: 8,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              backgroundColor: AppColors.parchment,
              valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
            ),
            const SizedBox(height: AppSpacing.xs8),
            Row(
              children: [
                Text(
                  QuestsStrings.progressLabel(
                    progress.complete ? def.target : progress.progress,
                    def.target,
                    lang,
                  ),
                  style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.schedule_outlined,
                      size: 14, color: AppColors.outline),
                  label: Text(s.deadlineWeekOrMonth(def), style: AppTextStyles.labelMd),
                ),
                const SizedBox(width: AppSpacing.xs8),
                Text(deadlineChipText, style: AppTextStyles.labelMd),
              ],
            ),
            const SizedBox(height: AppSpacing.xs8),
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.card_giftcard_outlined,
                      size: 14, color: AppColors.secondary),
                  label: Text(
                    _rewardLabel,
                    style: AppTextStyles.labelMd
                        .copyWith(color: AppColors.secondary),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: canClaim ? onClaim : null,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        claimed ? AppColors.parchment : AppColors.primary,
                    foregroundColor:
                        claimed ? AppColors.outline : Colors.white,
                  ),
                  child: Text(claimed ? s.claimedLabel : s.claimButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on QuestsStrings {
  String deadlineWeekOrMonth(QuestDef def) =>
      def.endsThisWeek ? deadlineWeekLabel : deadlineMonthLabel;
}

class BadgeMedallion extends StatelessWidget {
  const BadgeMedallion({
    super.key,
    required this.icon,
    required this.title,
    required this.earnedAt,
    required this.gold,
  });

  final IconData icon;
  final String title;
  final DateTime? earnedAt;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final earned = earnedAt != null;
    final gradient = earned
        ? (gold
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE8B93E), Color(0xFFB98A1F)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryContainer],
              ))
        : const LinearGradient(colors: [Color(0xFFE5E2DC), Color(0xFFD7D4CE)]);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: gradient,
            shape: BoxShape.circle,
            boxShadow: earned ? AppShadows.coffeeShadows(blurRadius: 12) : null,
          ),
          child: Center(
            child: Icon(
              earned ? icon : Icons.lock_outline,
              size: 40,
              color: earned ? Colors.white : AppColors.outline,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs8),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: earned ? AppColors.coffeeBean : AppColors.outline,
          ),
        ),
      ],
    );
  }
}

class _OfflineRetryBanner extends StatelessWidget {
  const _OfflineRetryBanner({
    required this.message,
    required this.cta,
    required this.onRetry,
  });

  final String message;
  final String cta;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.paperWhite,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_off_outlined, color: AppColors.error),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(child: Text(message)),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: onRetry, child: Text(cta)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBanner extends StatelessWidget {
  const _BottomBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm16),
      decoration: BoxDecoration(
        color: AppColors.primaryFixedTint.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadii.mdLg12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
