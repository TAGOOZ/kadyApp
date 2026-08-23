// حساب العميل — staff customer lookup (#013, FEATURES §6.4): debounced
// (300 ms) live search over customers by name/phone fragment, persisted
// recent-search chips (`lookup.recent`, tap fills + searches / long-press
// removes), fully-expanded profile cards (tier chip from lifetime points,
// stats grid, recent orders mini-list), manual reward grants through the
// reward sheet, walk-in visit registration with the same pending-stamp copy
// as the staff board (#012), and a per-phone activity log sheet fed by
// `staff_log`. A Postgres 42501 anywhere renders the same full-screen lock
// panel as the board until profiles.role is elevated.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_lookup.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/customer_lookup_repository.dart';
import '../../data/repos/staff_orders_repository.dart';
import 'widgets/customer_result_card.dart';
import 'widgets/manual_reward_sheet.dart';

class CustomerLookupScreen extends ConsumerStatefulWidget {
  const CustomerLookupScreen({super.key});

  @override
  ConsumerState<CustomerLookupScreen> createState() =>
      _CustomerLookupScreenState();
}

class _CustomerLookupScreenState extends ConsumerState<CustomerLookupScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  RecentSearchStore? _recents;
  List<String> _recentTerms = const [];
  List<CustomerProfile> _profiles = const [];
  bool _searching = false;
  bool _searched = false;
  bool _permissionDenied = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    ref.read(recentSearchesProvider.future).then((store) {
      if (!mounted) return;
      setState(() {
        _recents = store;
        _recentTerms = store.list();
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  LookupStrings get _strings =>
      LookupStrings.of(ref.read(localeNotifierProvider));

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -- Search -----------------------------------------------------------------

  /// Live search, debounced at 300 ms while typing.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _runSearch(value);
    });
  }

  /// Submit (keyboard search action / recent chip) runs immediately and
  /// records the term into the persisted recents.
  Future<void> _submitSearch(String value) async {
    _debounce?.cancel();
    await _runSearch(value);
    final term = value.trim();
    if (!mounted || term.isEmpty || _recents == null) return;
    await _recents!.add(term);
    setState(() => _recentTerms = _recents!.list());
  }

  Future<void> _runSearch(String value) async {
    final term = value.trim();
    if (term.isEmpty) {
      setState(() {
        _profiles = const [];
        _searched = false;
        _permissionDenied = false;
        _loadFailed = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final hits =
          await ref.read(customerLookupRepoProvider).search(term);
      final loaded = [
        for (final hit in hits)
          await ref.read(customerLookupRepoProvider).loadProfile(hit.phone),
      ];
      if (!mounted) return;
      setState(() {
        _profiles = loaded;
        _searching = false;
        _searched = true;
        _permissionDenied = false;
        _loadFailed = false;
      });
    } on StaffPermissionException {
      if (!mounted) return;
      setState(() {
        _permissionDenied = true;
        _searching = false;
        _searched = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _searching = false;
        _searched = false;
      });
    }
  }

  Future<void> _reloadProfile(String phone) async {
    try {
      final fresh =
          await ref.read(customerLookupRepoProvider).loadProfile(phone);
      if (!mounted) return;
      setState(() {
        _profiles = [
          for (final profile in _profiles)
            profile.phone == phone ? fresh : profile,
        ];
      });
    } catch (_) {
      // Stale card beats an error dialog on refresh hiccups.
    }
  }

  // -- Actions ----------------------------------------------------------------

  Future<void> _grantReward(CustomerProfile profile) async {
    final strings = _strings;
    final input = await ManualRewardSheet.show(context, strings);
    if (input == null || !mounted) return;
    try {
      await ref
          .read(customerLookupRepoProvider)
          .grantManualReward(profile.phone, input);
      if (!mounted) return;
      _showSnack(strings.rewardAddedToast);
      await _reloadProfile(profile.phone);
    } on StaffPermissionException {
      _showSnack(strings.lockTitle);
    } catch (_) {
      _showSnack(strings.errorGeneric);
    }
  }

  Future<void> _registerVisit(CustomerProfile profile) async {
    final strings = _strings;
    final spend = await _promptSpend();
    if (spend == null || !mounted) return;
    try {
      final recorded = await ref
          .read(customerLookupRepoProvider)
          .registerVisit(
            CheckInInput(phone: profile.phone, spendEgp: spend),
          );
      if (!mounted) return;
      _showSnack(recorded.loyaltyPending
          ? strings.visitPendingToast
          : strings.visitOkToast);
      await _reloadProfile(profile.phone);
    } on StaffPermissionException {
      _showSnack(strings.lockTitle);
    } catch (_) {
      _showSnack(strings.errorGeneric);
    }
  }

  /// Spend amount dialog for تسجيل زيارة; null when dismissed/invalid-cancelled.
  Future<int?> _promptSpend() {
    final strings = _strings;
    final controller = TextEditingController();
    String? error;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(strings.visitDialogTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.visitFieldSpend,
              border: const OutlineInputBorder(),
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () {
                final spend = int.tryParse(controller.text.trim());
                if (spend == null || spend < 0) {
                  setDialogState(() => error = strings.visitErrorSpend);
                  return;
                }
                Navigator.of(dialogContext).pop(spend);
              },
              child: Text(strings.visitConfirmCta),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openActivityLog(CustomerProfile profile) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => _ActivityLogSheet(
        strings: _strings,
        entriesFuture:
            ref.read(customerLookupRepoProvider).activityLog(profile.phone),
      ),
    );
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = LookupStrings.of(lang);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(strings.screenTitle),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter16,
              AppSpacing.sm16,
              AppSpacing.gutter16,
              AppSpacing.xs8,
            ),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: _submitSearch,
              decoration: InputDecoration(
                hintText: strings.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (_recentTerms.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.gutter16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.recentTitle,
                    style: AppTextStyles.bodySm
                        .copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: AppSpacing.xs8,
                    runSpacing: AppSpacing.xs8,
                    children: [
                      for (final term in _recentTerms)
                        // Long-press removes the chip from the persisted list.
                        GestureDetector(
                          onLongPress: () async {
                            await _recents?.remove(term);
                            if (!mounted) return;
                            setState(() => _recentTerms = _recents!.list());
                          },
                          child: ActionChip(
                            label: Text(term),
                            tooltip: strings.recentTitle,
                            onPressed: () {
                              _searchController.text = term;
                              _submitSearch(term);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(child: _buildResults(strings)),
        ],
      ),
    );
  }

  Widget _buildResults(LookupStrings strings) {
    if (_permissionDenied) {
      return _LockPanel(
        strings: strings,
        onRetry: () => _runSearch(_searchController.text),
      );
    }
    if (_loadFailed) {
      return _RetryPanel(
        strings: strings,
        onRetry: () => _runSearch(_searchController.text),
      );
    }
    if (_searching && _profiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_profiles.isEmpty) {
      return Center(
        child: Text(
          _searched ? strings.noResults : strings.emptyTermHint,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyLg.copyWith(color: AppColors.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.gutter16),
      itemCount: _profiles.length,
      itemBuilder: (context, index) {
        final profile = _profiles[index];
        return CustomerResultCard(
          profile: profile,
          strings: strings,
          onAddReward: () => _grantReward(profile),
          onRegisterVisit: () => _registerVisit(profile),
          onOpenActivityLog: () => _openActivityLog(profile),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen panels — identical pattern to the staff board lock panel
// ---------------------------------------------------------------------------

/// قفل 🔒 بلا صلاحية موظف — RLS denied the read/write (42501); points at SQL.
class _LockPanel extends StatelessWidget {
  const _LockPanel({required this.strings, required this.onRetry});

  final LookupStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline,
                size: 56, color: AppColors.primary.withValues(alpha: 0.7)),
            const SizedBox(height: AppSpacing.sm16),
            Text(strings.lockTitle,
                style: AppTextStyles.titleMd, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs8),
            Text(
              strings.lockHint,
              style:
                  AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm16),
            FilledButton.tonal(onPressed: onRetry, child: Text(strings.retryCta)),
          ],
        ),
      ),
    );
  }
}

class _RetryPanel extends StatelessWidget {
  const _RetryPanel({required this.strings, required this.onRetry});

  final LookupStrings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.outline),
          const SizedBox(height: AppSpacing.sm16),
          Text(strings.loadFailed, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm16),
          FilledButton(onPressed: onRetry, child: Text(strings.retryCta)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity log sheet — staff_log rows for one phone, newest first
// ---------------------------------------------------------------------------

class _ActivityLogSheet extends StatelessWidget {
  const _ActivityLogSheet({required this.strings, required this.entriesFuture});

  final LookupStrings strings;
  final Future<List<StaffActivity>> entriesFuture;

  String _title(StaffActivity entry) {
    switch (entry.action) {
      case 'manual_reward':
        return strings.activityReward(
          _rewardLabel('${entry.detail['reward']}'),
          _reasonLabel('${entry.detail['reason']}'),
        );
      case 'checkin':
        return strings.activityVisitLine;
      default:
        return entry.action;
    }
  }

  String _rewardLabel(String wire) => switch (wire) {
        'points25' => strings.rewardPoints25,
        'free_drink' => strings.rewardFreeDrink,
        'free_topping' => strings.rewardFreeTopping,
        _ => wire,
      };

  String _reasonLabel(String wire) => switch (wire) {
        'late_apology' => strings.reasonLateApology,
        'new_guest' => strings.reasonNewGuest,
        'other' => strings.reasonOther,
        _ => wire,
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.activityLogTitle, style: AppTextStyles.titleMd),
            const SizedBox(height: AppSpacing.xs8),
            Flexible(
              child: FutureBuilder<List<StaffActivity>>(
                future: entriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.md24),
                      child:
                          Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.md24),
                      child: Text(strings.errorGeneric),
                    );
                  }
                  final entries = snapshot.data ?? const [];
                  if (entries.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.md24),
                      child: Center(
                        child: Text(
                          strings.activityEmpty,
                          style: AppTextStyles.bodySm
                              .copyWith(color: AppColors.textMuted),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final note =
                          '${entry.detail['note'] ?? ''}'.trim();
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          entry.action == 'manual_reward'
                              ? Icons.card_giftcard_outlined
                              : Icons.how_to_reg_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        title: Text(_title(entry)),
                        subtitle: note.isEmpty
                            ? null
                            : Text(note, style: AppTextStyles.bodySm),
                        trailing: Text(
                          formatLookupWhenUtc(entry.atUtc),
                          style: AppTextStyles.labelMd
                              .copyWith(color: AppColors.textMuted),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
