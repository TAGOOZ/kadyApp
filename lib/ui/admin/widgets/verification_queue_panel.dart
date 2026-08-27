// Verification queue panel — RISK-06 (issue #51).
// Staff/Admin UX for the manual verification queue. Arabic-first RTL,
// Heritage Hearth tokens only, Western digits 0123 in both languages §11.11.
// Shows realtime verification_requests WHERE status='pending' joined to orders
// and customers (via RiskProfileRepo + CustomerLookupRepo seam), newest first,
// limit 50, with chips for risk_level (low=green, medium=amber, high=red via
// AppColors tokens only — secondary/error/success, never raw hex).
// Detail card per pending order matches plan §10 copy, RTL, Western digits.
// Actions: [Confirm] → VerificationService.confirmByStaff(orderId) optimistic UI,
// [Reject] → rejectByStaff + rejectReason='verification_rejected'.
// Detail enrichment on expand: risk profile counts, device relationships,
// address history, risk_events last 5 (parallel-fetch pattern bounded).
// State: StreamProvider<List<PendingVerification>> realtime + FutureProvider for
// enrichment, retry: noAutoRetry so error UI renders instantly; loading shimmer,
// empty state لا توجد طلبات تحتاج تحقق, offline snackbar Failed — Retry preserving queue.
// Theme: no fontSize:/Color(0x…) outside app_theme.dart, AppSpacing/AppRadii,
// motion easeOutCubic only, respects MediaQuery.disableAnimations, contrast ≥4.5:1.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_risk.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/verification_queue_repository.dart';
import '../../../data/repos/verification_repository.dart';
import '../../../domain/risk_engine.dart';

class VerificationQueuePanel extends ConsumerStatefulWidget {
  const VerificationQueuePanel({super.key});

  @override
  ConsumerState<VerificationQueuePanel> createState() => _VerificationQueuePanelState();
}

class _VerificationQueuePanelState extends ConsumerState<VerificationQueuePanel> {
  final Set<String> _optimisticRemoved = {};
  final Set<String> _confirming = {};
  final Set<String> _rejecting = {};

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onConfirm(PendingVerification item) async {
    final strings = RiskStrings.of(ref.read(localeNotifierProvider));
    setState(() {
      _optimisticRemoved.add(item.orderId);
      _confirming.add(item.orderId);
    });
    try {
      await ref.read(verificationServiceProvider).confirmByStaff(orderId: item.orderId);
      if (!mounted) return;
      _showSnack(strings.confirmSuccess);
    } on VerificationPermissionException {
      if (!mounted) return;
      setState(() => _optimisticRemoved.remove(item.orderId));
      _showSnack(strings.lockTitle);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimisticRemoved.remove(item.orderId));
      _showSnack(strings.failedSnack);
    } finally {
      if (mounted) setState(() => _confirming.remove(item.orderId));
    }
  }

  Future<void> _onReject(PendingVerification item) async {
    final strings = RiskStrings.of(ref.read(localeNotifierProvider));
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: 'verification_rejected');
        return AlertDialog(
          title: Text(strings.rejectTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: strings.rejectHint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim().isEmpty ? 'verification_rejected' : controller.text.trim()),
              child: Text(strings.rejectConfirm),
            ),
          ],
        );
      },
    );
    if (reason == null) return;
    setState(() {
      _optimisticRemoved.add(item.orderId);
      _rejecting.add(item.orderId);
    });
    try {
      await ref.read(verificationServiceProvider).rejectByStaff(orderId: item.orderId, reason: reason);
      if (!mounted) return;
      _showSnack(strings.rejectSuccess);
    } on VerificationPermissionException {
      if (!mounted) return;
      setState(() => _optimisticRemoved.remove(item.orderId));
      _showSnack(strings.lockTitle);
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimisticRemoved.remove(item.orderId));
      _showSnack(strings.failedSnack);
    } finally {
      if (mounted) setState(() => _rejecting.remove(item.orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = RiskStrings.of(lang);
    final access = ref.watch(verificationAccessProvider);

    return access.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => error is VerificationPermissionException
          ? _LockPanel(strings: strings, onRetry: () => ref.invalidate(verificationAccessProvider))
          : _RetryPanel(strings: strings, onRetry: () => ref.invalidate(verificationAccessProvider)),
      data: (_) => _buildQueue(strings, lang),
    );
  }

  Widget _buildQueue(RiskStrings strings, AppLang lang) {
    final queueAsync = ref.watch(verificationQueueProvider);

    // Offline preserve: listen for errors and show snackbar while keeping previous data
    ref.listen<AsyncValue<List<PendingVerification>>>(verificationQueueProvider, (prev, next) {
      next.whenOrNull(
        error: (error, _) {
          if (error is! VerificationPermissionException) {
            // Preserve queue — show snackbar instead of wiping list
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showSnack(strings.failedSnack);
            });
          }
        },
      );
    });

    return queueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        if (error is VerificationPermissionException) {
          return _LockPanel(strings: strings, onRetry: () => ref.invalidate(verificationQueueProvider));
        }
        // If we have previous data, preserve it (offline) — hasValue retains last data on error
        if (queueAsync.hasValue) {
          final previous = queueAsync.value!;
          if (previous.isNotEmpty) {
            // Preserve queue but indicate error via snackbar already shown via listen
            return _QueueList(
              items: previous.where((e) => !_optimisticRemoved.contains(e.orderId)).toList(),
              strings: strings,
              lang: lang,
              confirming: _confirming,
              rejecting: _rejecting,
              onConfirm: _onConfirm,
              onReject: _onReject,
            );
          }
        }
        return _RetryPanel(strings: strings, onRetry: () => ref.invalidate(verificationQueueProvider));
      },
      data: (items) {
        final visible = items.where((e) => !_optimisticRemoved.contains(e.orderId)).toList();
        if (visible.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_outlined, size: 48, color: AppColors.outline),
                  const SizedBox(height: AppSpacing.xs8),
                  Text(
                    strings.emptyQueue,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          );
        }
        return _QueueList(
          items: visible,
          strings: strings,
          lang: lang,
          confirming: _confirming,
          rejecting: _rejecting,
          onConfirm: _onConfirm,
          onReject: _onReject,
        );
      },
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({
    required this.items,
    required this.strings,
    required this.lang,
    required this.confirming,
    required this.rejecting,
    required this.onConfirm,
    required this.onReject,
  });

  final List<PendingVerification> items;
  final RiskStrings strings;
  final AppLang lang;
  final Set<String> confirming;
  final Set<String> rejecting;
  final Future<void> Function(PendingVerification) onConfirm;
  final Future<void> Function(PendingVerification) onReject;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.gutter16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm16),
          child: _VerificationCard(
            item: item,
            strings: strings,
            lang: lang,
            isConfirming: confirming.contains(item.orderId),
            isRejecting: rejecting.contains(item.orderId),
            onConfirm: () => onConfirm(item),
            onReject: () => onReject(item),
          ),
        );
      },
    );
  }
}

class _VerificationCard extends ConsumerStatefulWidget {
  const _VerificationCard({
    required this.item,
    required this.strings,
    required this.lang,
    required this.isConfirming,
    required this.isRejecting,
    required this.onConfirm,
    required this.onReject,
  });

  final PendingVerification item;
  final RiskStrings strings;
  final AppLang lang;
  final bool isConfirming;
  final bool isRejecting;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  ConsumerState<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends ConsumerState<_VerificationCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _expandController;
  late final Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _expandAnimation = CurvedAnimation(parent: _expandController, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggle() {
    final disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() => _expanded = !_expanded);
    if (disableAnimations) {
      if (_expanded) {
        _expandController.value = 1;
      } else {
        _expandController.value = 0;
      }
      return;
    }
    if (_expanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  Color _levelBg(RiskLevel? level) => switch (level) {
        RiskLevel.low => AppColors.successContainer,
        RiskLevel.medium => AppColors.secondaryContainer,
        RiskLevel.high => AppColors.error,
        null => AppColors.parchment,
      };

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final strings = widget.strings;
    final lang = widget.lang;
    final reasonStrings = RiskReasonStrings.of(lang);

    final humanizedReasons = item.riskReasons.map(reasonStrings.humanize).where((s) => s.isNotEmpty).toList();
    final reasonsText = humanizedReasons.isEmpty ? '-' : humanizedReasons.map((r) => '• $r').join('  ');

    final levelWire = item.riskLevel?.wireName ?? 'medium';
    final levelLabel = strings.levelLabel(levelWire);
    final actionWire = item.riskAction?.wireName ?? 'needs_verification';
    final scoreText = '${item.riskScore}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius: BorderRadius.circular(AppRadii.md8),
        boxShadow: AppShadows.coffeeShadows(),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md8),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.secondary),
                  const SizedBox(width: AppSpacing.xs8),
                  Expanded(
                    child: Text(
                      strings.verificationRequired,
                      style: AppTextStyles.titleSm.copyWith(color: AppColors.coffeeBean, fontWeight: FontWeight.w700),
                    ),
                  ),
                  // Level badge — single source, top-right only (deduplicated)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _levelBg(item.riskLevel),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      levelLabel,
                      style: AppTextStyles.labelMd.copyWith(
                        color: item.riskLevel == RiskLevel.high ? Colors.white : AppColors.coffeeBean,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs8),
              Text(
                '${strings.customerLabel}: ${item.customerName ?? ''}  ${strings.phoneLabel}: ${item.phone}',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                '${strings.orderLabel}: #${item.displayNumber}  ${strings.totalLabel}: ${item.totalEgp ?? '-'} EGP',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.coffeeBean, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: AppSpacing.xs8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${strings.riskScoreLabel}: ',
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                  ),
                  Text(
                    scoreText,
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.coffeeBean, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${strings.riskLevelLabel}: $levelLabel',
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                  ),
                  Text(
                    '${strings.actionLabel}: $actionWire',
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${strings.reasonsLabel}: $reasonsText',
                style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.xs8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.isConfirming || widget.isRejecting ? null : widget.onConfirm,
                      child: widget.isConfirming
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(strings.confirmCta),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.isConfirming || widget.isRejecting ? null : widget.onReject,
                      child: widget.isRejecting
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(strings.rejectCta),
                    ),
                  ),
                ],
              ),
              SizeTransition(
                sizeFactor: _expandAnimation,
                child: _EnrichmentSection(
                  item: item,
                  strings: strings,
                  lang: lang,
                  expanded: _expanded,
                ),
              ),
              if (!_expanded)
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(Icons.expand_more, size: 16, color: AppColors.textMuted.withValues(alpha: 0.7)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnrichmentSection extends ConsumerWidget {
  const _EnrichmentSection({
    required this.item,
    required this.strings,
    required this.lang,
    required this.expanded,
  });

  final PendingVerification item;
  final RiskStrings strings;
  final AppLang lang;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!expanded) return const SizedBox.shrink();
    final key = EnrichmentKey(phone: item.phone, deviceId: item.deviceId, addressId: item.addressId);
    final enrichmentAsync = ref.watch(verificationEnrichmentProvider(key));

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm16),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadii.md8),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.15)),
        ),
        child: enrichmentAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
          error: (e, _) => Text(strings.loadFailed, style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted)),
          data: (enrichment) {
            final profile = enrichment.riskProfile;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.expandedProfileTitle, style: AppTextStyles.titleSm.copyWith(color: AppColors.coffeeBean)),
                const SizedBox(height: 4),
                if (profile != null)
                  Text(
                    '${profile.failedDeliveries} ${strings.failedDeliveriesLabel} • ${profile.cancelledOrders} ${strings.cancelledLabel} • ${profile.rejectedOrders} ${strings.rejectedLabel}',
                    style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                  )
                else
                  Text('-', style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: AppSpacing.xs8),
                Text(strings.expandedDeviceTitle, style: AppTextStyles.titleSm.copyWith(color: AppColors.coffeeBean)),
                const SizedBox(height: 4),
                if (enrichment.deviceRelatedPhones.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Chip(
                        label: Text(strings.deviceCount(enrichment.deviceRelatedPhones.length), style: AppTextStyles.labelMd),
                        backgroundColor: AppColors.parchment,
                      ),
                      for (final p in enrichment.deviceRelatedPhones)
                        Chip(
                          label: Text(p, style: AppTextStyles.labelMd),
                          backgroundColor: AppColors.paperWhite,
                        ),
                      Chip(
                        label: Text(strings.deviceSharedBadge, style: AppTextStyles.labelMd.copyWith(color: AppColors.secondary)),
                        backgroundColor: AppColors.secondaryContainer.withValues(alpha: 0.3),
                      ),
                    ],
                  )
                else
                  Text(strings.deviceCount(0), style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: AppSpacing.xs8),
                Text(strings.expandedAddressTitle, style: AppTextStyles.titleSm.copyWith(color: AppColors.coffeeBean)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(strings.addressOrders(enrichment.addressOrdersCount), style: AppTextStyles.labelMd),
                      backgroundColor: AppColors.parchment,
                    ),
                    if (enrichment.addressShared)
                      Chip(
                        label: Text(strings.addressSharedBadge, style: AppTextStyles.labelMd.copyWith(color: AppColors.error)),
                        backgroundColor: AppColors.error.withValues(alpha: 0.12),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs8),
                Text(strings.expandedEventsTitle, style: AppTextStyles.titleSm.copyWith(color: AppColors.coffeeBean)),
                const SizedBox(height: 4),
                if (enrichment.recentEvents.isEmpty)
                  Text(strings.riskEventsEmpty, style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted))
                else
                  Column(
                    children: [
                      for (final ev in enrichment.recentEvents)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.history, size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${ev.eventType} • ${ev.phone ?? ''}',
                                  style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LockPanel extends StatelessWidget {
  const _LockPanel({required this.strings, required this.onRetry});
  final RiskStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: AppColors.outline),
            const SizedBox(height: AppSpacing.xs8),
            Text(strings.lockTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              strings.lockHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.xs8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(strings.retryCta),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryPanel extends StatelessWidget {
  const _RetryPanel({required this.strings, required this.onRetry});
  final RiskStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.outline),
          const SizedBox(height: AppSpacing.xs8),
          Text(strings.loadFailed, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xs8),
          FilledButton(onPressed: onRetry, child: Text(strings.retryCta)),
        ],
      ),
    );
  }
}
