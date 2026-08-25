// Campaigns tab (ARCH-02 split): extracted from admin_dashboard_screen.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/strings_admin.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/admin_campaign_repository.dart';
import '../../../data/repos/admin_db.dart';
import '../widgets/campaign_card.dart';

void _showErrorToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class CampaignsTab extends ConsumerStatefulWidget {
  const CampaignsTab({
    super.key,
    required this.strings,
    required this.onAccessDenied,
  });

  final AdminStrings strings;
  final VoidCallback onAccessDenied;

  @override
  ConsumerState<CampaignsTab> createState() => CampaignsTabState();
}

class CampaignsTabState extends ConsumerState<CampaignsTab> {
  List<Campaign>? _campaigns;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final campaigns =
          await ref.read(campaignRepositoryProvider).listAll();
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _loading = false;
      });
    } on AdminAccessDeniedException {
      widget.onAccessDenied();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Campaign campaign, bool active) async {
    final index = _campaigns!.indexOf(campaign);
    setState(() => _campaigns![index] = _copyWith(campaign, active: active));
    try {
      await ref.read(campaignRepositoryProvider).toggleActive(campaign, active);
    } catch (_) {
      if (!mounted) return;
      setState(() => _campaigns![index] = campaign);
      _showErrorToast(context, widget.strings.revertedError);
    }
  }

  Campaign _copyWith(Campaign c, {bool? active}) => Campaign(
        id: c.id,
        kind: c.kind,
        active: active ?? c.active,
        nameAr: c.nameAr,
        startsAt: c.startsAt,
        endsAt: c.endsAt,
      );

  Future<void> openCreateDialog() async {
    final result = await showCampaignDialog(
      context: context,
      strings: widget.strings,
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(campaignRepositoryProvider).create(
            kind: result.kind,
            nameAr: result.nameAr,
            startsAt: result.startsAt,
            endsAt: result.endsAt,
          );
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
    }
    await _load();
  }

  Future<void> _edit(Campaign campaign) async {
    final result = await showCampaignDialog(
      context: context,
      strings: widget.strings,
      initial: campaign,
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(campaignRepositoryProvider).updateDates(
            campaign.id,
            kind: result.kind,
            nameAr: result.nameAr,
            startsAt: result.startsAt,
            endsAt: result.endsAt,
          );
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
    }
    await _load();
  }

  Future<void> _delete(Campaign campaign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.strings.deleteCampaignTitle),
        content: Text(widget.strings.deleteCampaignBodyFn(
            campaign.nameAr?.isNotEmpty == true ? campaign.nameAr! : widget.strings.kindLabel(campaign.kind))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(widget.strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(widget.strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(campaignRepositoryProvider).delete(campaign.id);
    } catch (_) {
      if (!mounted) return;
      _showErrorToast(context, widget.strings.revertedError);
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final campaigns = _campaigns ?? const <Campaign>[];
    if (campaigns.isEmpty) {
      return Center(child: Text(widget.strings.noData));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        itemCount: campaigns.length,
        itemBuilder: (context, index) {
          final campaign = campaigns[index];
          return CampaignCard(
            campaign: campaign,
            strings: widget.strings,
            onToggleActive: (active) => _toggle(campaign, active),
            onEdit: () => _edit(campaign),
            onDelete: () => _delete(campaign),
          );
        },
      ),
    );
  }
}
