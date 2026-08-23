// Checkout (issue #003 / FEATURES §3.5): mode-aware details form, totals
// with the flat delivery fee (no service-charge row in v1, §11.13), real
// loyalty earn preview (#007 rules) and a fixed cash payment line. The
// loyalty box gains a points-redemption toggle when an affordable reward
// exists (#007): free drink zeroes the highest-priced drink line, other
// rewards ride along as a notes marker for staff. Submit inserts into
// public.orders via OrdersRepo with a 30 s client debounce (ADR-0010),
// encodes redemptions as a `[REDEEMED:{type}:{cost}]` notes prefix, then
// credits loyalty exactly once through LoyaltyController.creditProcessedOrder;
// guests are bounced to the save prompt because RLS forbids their orders.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_checkout.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/orders_repository.dart';
import '../../domain/auth_controller.dart';
import '../../domain/cart_controller.dart';
import '../../domain/loyalty_controller.dart';
import '../../domain/loyalty_rules.dart';
import '../auth/guest_save_prompt.dart';

/// Saved delivery addresses for the signed-in customer.
final addressesProvider =
    FutureProvider.autoDispose.family<List<SavedAddress>, String>(
  (ref, googleUserId) =>
      ref.watch(ordersRepoProvider).fetchAddresses(googleUserId),
);

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  static const _debounce = Duration(seconds: 30); // ADR-0010 client side

  final _tableController = TextEditingController();
  final _addrTextController = TextEditingController();

  int? _areaIndex; // null · 0 داخل · 1 تراس — mutually exclusive with table #
  AddressLabel _newAddrLabel = AddressLabel.home;
  bool _showAddrForm = false;
  bool _savingAddress = false;
  bool _submitting = false;
  bool _locked = false;
  bool _redeemed = false; // loyalty redemption toggle (#007)
  Timer? _unlockTimer;
  String? _validationError;

  @override
  void dispose() {
    _unlockTimer?.cancel();
    _tableController.dispose();
    _addrTextController.dispose();
    super.dispose();
  }

  void _showError(CheckoutStrings strings, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ));
  }

  Future<void> _saveAddress(String googleUserId, CheckoutStrings s) async {
    final text = _addrTextController.text.trim();
    if (text.isEmpty) return;
    setState(() => _savingAddress = true);
    try {
      final saved =
          await ref.watch(ordersRepoProvider).saveAddress(SavedAddressInput(
                googleUserId: googleUserId,
                label: _newAddrLabel,
                addressText: text,
              ));
      ref.invalidate(addressesProvider(googleUserId));
      ref.read(checkoutDraftProvider.notifier).setAddressId(saved.id);
      setState(() {
        _showAddrForm = false;
        _addrTextController.clear();
      });
    } catch (_) {
      if (mounted) _showError(s, s.addressSaveFailed);
    } finally {
      if (mounted) setState(() => _savingAddress = false);
    }
  }

  Future<void> _submit({
    required CheckoutStrings s,
    required OrderMode mode,
    required List<OrderItemPayload> items,
    required int subtotalEgp,
    required int feeEgp,
    required int previewPoints,
    Redemption? redemption,
  }) async {
    if (_submitting || _locked) return;

    final auth = ref.read(authControllerProvider);
    if (auth.phase != AuthPhase.ready || auth.googleUser == null) {
      await showGuestSavePrompt(context);
      return;
    }

    final draftState = ref.read(checkoutDraftProvider);
    final timing = draftState.pickupTiming ?? const PickupTiming.now();
    final candidate = CheckoutDraft(
      mode: mode,
      tableArea: mode == OrderMode.dineIn ? _dineInDetail(s) : null,
      pickupTiming: mode == OrderMode.pickup ? timing : null,
      addressId: mode == OrderMode.delivery
          ? ref.read(checkoutDraftProvider).addressId
          : null,
    );
    if (!candidate.canSubmit) {
      setState(() => _validationError = switch (mode) {
            OrderMode.dineIn => s.dineInMissingError,
            OrderMode.pickup => s.pickupMissingError,
            OrderMode.delivery => s.addressRequiredError,
          });
      return;
    }
    setState(() => _validationError = null);

    // Redemption rides as a notes prefix — `[REDEEMED:{type}:{cost}]` — so no
    // schema change is needed (accepted trade-off, see slice report).
    final draftNotes = draftState.notes.trim();
    final notes = [
      if (redemption != null)
        '[REDEEMED:${redemption.type.key}:${redemption.costPts}]',
      if (draftNotes.isNotEmpty) draftNotes,
    ].join(' ');

    final notifier = ref.read(checkoutDraftProvider.notifier);
    final googleUserId = auth.googleUser!.id;
    setState(() => _submitting = true);
    try {
      final placed = await ref.watch(ordersRepoProvider).placeOrder(NewOrder(
            mode: mode,
            googleUserId: googleUserId,
            phone: auth.phone,
            items: items,
            subtotalEgp: subtotalEgp,
            deliveryFeeEgp: feeEgp,
            totalEgp: totalOf(subtotalEgp: subtotalEgp, deliveryFeeEgp: feeEgp),
            pointsPreview: previewPoints,
            tableArea: candidate.tableArea,
            pickupSlotUtc: timing.isNow ? null : timing.slotUtc,
            addressId: candidate.addressId,
            notes: notes.isEmpty ? null : notes,
          ));
      // Real earn path (#007): credit exactly once for the placed order, on
      // the discounted spend actually collected. Fire-and-forget so the
      // confirmation navigation is never delayed by the loyalty round-trip.
      unawaited(ref
          .read(loyaltyProvider.notifier)
          .creditProcessedOrder(
            orderId: placed.id,
            subtotalEgp: subtotalEgp,
            dineIn: mode == OrderMode.dineIn,
            redemption: redemption,
          ));
      _unlockTimer?.cancel();
      _locked = true; // stay debounced for 30 s even after navigating away
      _unlockTimer = Timer(_debounce, () {
        if (mounted) setState(() => _locked = false);
      });
      if (!mounted) return;
      context.pushReplacement(
        '/confirmation',
        extra: ConfirmationArgs(
          displayNumber: placed.displayNumber,
          mode: mode,
          items: items,
          subtotalEgp: subtotalEgp,
          deliveryFeeEgp: feeEgp,
          totalEgp:
              totalOf(subtotalEgp: subtotalEgp, deliveryFeeEgp: feeEgp),
          pointsPreview: previewPoints,
        ),
      );
      notifier.reset();
    } catch (_) {
      // Standard error policy: snackbar + form preserved for retry.
      if (mounted) _showError(s, s.submitFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _dineInDetail(CheckoutStrings s) {
    if (_areaIndex != null) {
      return _areaIndex == 0 ? s.areaInside : s.areaTerrace;
    }
    final table = _tableController.text.trim();
    return table.isEmpty ? null : '${s.tableFieldLabel} $table';
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final s = CheckoutStringsCatalog.of(lang);

    final draft = ref.watch(checkoutDraftProvider);
    final mode = draft.mode ?? OrderMode.pickup; // flow guarantees a pick
    final lines = ref.watch(cartProvider);
    final subtotal = ref.watch(subtotalProvider);

    final configuredFee =
        ref.watch(deliveryFeeProvider).asData?.value ?? defaultDeliveryFeeEgp;
    final fee = deliveryFeeFor(mode, configuredFeeEgp: configuredFee);

    // Loyalty (#007): admin-tuned rules (seed constants offline) + live state
    // drive the redemption toggle, the discounted subtotal and the earn preview.
    final loyalty = ref.watch(loyaltyProvider);
    final rulesConfig =
        ref.watch(loyaltyConfigProvider).asData?.value ?? LoyaltyRulesConfig.fallback;
    final hasDrinkLine =
        lines.any((line) => isDrinkCategorySlug(line.item.categorySlug));
    final redemption = redeemable(
      loyalty,
      hasDrinkLine: hasDrinkLine,
      config: rulesConfig,
    );
    final redeemed = _redeemed && redemption != null;
    final discountEgp =
        redeemed && redemption.type == RedemptionType.freeDrink
            ? drinkLineDiscountEgp(lines
                .map((line) => (
                      categorySlug: line.item.categorySlug,
                      lineTotalEgp: line.lineTotalEgp,
                    ))
                .toList())
            : 0;
    final subtotalAfterRedemption =
        subtotal - discountEgp > 0 ? subtotal - discountEgp : 0;
    final total = totalOf(
        subtotalEgp: subtotalAfterRedemption, deliveryFeeEgp: fee);
    final points = earnedFor(
      subtotalEgp: subtotalAfterRedemption,
      dineIn: mode == OrderMode.dineIn,
      pointsPer10: rulesConfig.pointsPer10Egp,
      dineInMultiplier: rulesConfig.dineInMultiplier,
      doubleWindow: loyalty.doubleNextOrder,
    );

    final items = [
      for (final line in lines)
        OrderItemPayload(
          id: line.item.id,
          nameAr: line.item.nameAr,
          qty: line.qty,
          unitTotalEgp: line.unitPriceEgp,
          config: line.config,
        ),
    ];

    final modeName = switch (mode) {
      OrderMode.dineIn => s.modeDineIn,
      OrderMode.pickup => s.modePickup,
      OrderMode.delivery => s.modeDelivery,
    };
    final paymentLine = mode == OrderMode.delivery
        ? s.paymentCashOnDelivery
        : s.paymentCashHere;

    return Scaffold(
      appBar: AppBar(title: Text(s.checkoutTitle)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter16,
                AppSpacing.xs8,
                AppSpacing.gutter16,
                AppSpacing.lg32,
              ),
              children: [
                Row(
                  children: [
                    Text(s.sectionDetails, style: AppTextStyles.titleMd),
                    const Spacer(),
                    Chip(label: Text(modeName)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs8),
                _ModeDetailsCard(
                  mode: mode,
                  strings: s,
                  tableController: _tableController,
                  areaIndex: _areaIndex,
                  onTableChanged: (value) => setState(() {
                    _areaIndex = null;
                    ref
                        .read(checkoutDraftProvider.notifier)
                        .setTableArea(value);
                  }),
                  onAreaSelected: (index) {
                    _tableController.clear();
                    ref
                        .read(checkoutDraftProvider.notifier)
                        .setTableArea(index == 0 ? s.areaInside : s.areaTerrace);
                    setState(() => _areaIndex = index);
                  },
                  addrTextController: _addrTextController,
                  newAddrLabel: _newAddrLabel,
                  onNewAddrLabelSelected: (label) =>
                      setState(() => _newAddrLabel = label),
                  showAddrForm: _showAddrForm,
                  onToggleAddrForm: () =>
                      setState(() => _showAddrForm = !_showAddrForm),
                  savingAddress: _savingAddress,
                  onSaveAddress: () {
                    final gid = ref.read(authControllerProvider).googleUser?.id;
                    if (gid == null || gid.isEmpty) return;
                    _saveAddress(gid, s);
                  },
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: AppSpacing.xs8),
                  Text(
                    _validationError!,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm16),
                _TotalsCard(
                  strings: s,
                  subtotalEgp: subtotalAfterRedemption,
                  feeEgp: fee,
                  totalEgp: total,
                  isDelivery: mode == OrderMode.delivery,
                ),
                const SizedBox(height: AppSpacing.sm16),
                _LoyaltyBanner(
                  strings: s,
                  points: points,
                  redemption: redemption,
                  redeemed: redeemed,
                  remainingPoints: redeemed
                      ? loyalty.points - redemption.costPts
                      : loyalty.points,
                  onToggleRedeem: redemption == null
                      ? null
                      : (value) =>
                          setState(() => _redeemed = value ?? false),
                ),
                const SizedBox(height: AppSpacing.sm16),
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 20),
                    const SizedBox(width: AppSpacing.xs8),
                    Expanded(child: Text(paymentLine, style: AppTextStyles.bodySm)),
                  ],
                ),
              ],
            ),
          ),
          _SubmitBar(
            label: s.confirmCta,
            totalEgp: total,
            strings: s,
            busy: _submitting || _locked,
            onSubmit: () => _submit(
              s: s,
              mode: mode,
              items: items,
              subtotalEgp: subtotalAfterRedemption,
              feeEgp: fee,
              previewPoints: points,
              redemption: redeemed ? redemption : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeDetailsCard extends StatelessWidget {
  const _ModeDetailsCard({
    required this.mode,
    required this.strings,
    required this.tableController,
    required this.areaIndex,
    required this.onTableChanged,
    required this.onAreaSelected,
    required this.addrTextController,
    required this.newAddrLabel,
    required this.onNewAddrLabelSelected,
    required this.showAddrForm,
    required this.onToggleAddrForm,
    required this.savingAddress,
    required this.onSaveAddress,
  });

  final OrderMode mode;
  final CheckoutStrings strings;
  final TextEditingController tableController;
  final int? areaIndex;
  final ValueChanged<String> onTableChanged;
  final ValueChanged<int?> onAreaSelected;
  final TextEditingController addrTextController;
  final AddressLabel newAddrLabel;
  final ValueChanged<AddressLabel> onNewAddrLabelSelected;
  final bool showAddrForm;
  final VoidCallback onToggleAddrForm;
  final bool savingAddress;
  final VoidCallback onSaveAddress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: switch (mode) {
          OrderMode.dineIn => _DineInDetails(
              strings: strings,
              controller: tableController,
              areaIndex: areaIndex,
              onTableChanged: onTableChanged,
              onAreaSelected: onAreaSelected,
            ),
          OrderMode.pickup => _PickupDetails(strings: strings),
          OrderMode.delivery => _DeliveryDetails(
              strings: strings,
              textController: addrTextController,
              newLabel: newAddrLabel,
              onNewLabel: onNewAddrLabelSelected,
              showForm: showAddrForm,
              onToggleForm: onToggleAddrForm,
              saving: savingAddress,
              onSave: onSaveAddress,
            ),
        },
      ),
    );
  }
}

class _DineInDetails extends StatelessWidget {
  const _DineInDetails({
    required this.strings,
    required this.controller,
    required this.areaIndex,
    required this.onTableChanged,
    required this.onAreaSelected,
  });

  final CheckoutStrings strings;
  final TextEditingController controller;
  final int? areaIndex;
  final ValueChanged<String> onTableChanged;
  final ValueChanged<int?> onAreaSelected;

  @override
  Widget build(BuildContext context) {
    final areas = [strings.areaInside, strings.areaTerrace];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          onChanged: onTableChanged,
          decoration: InputDecoration(
            labelText: strings.tableFieldLabel,
            hintText: strings.tableFieldHint,
            border: const OutlineInputBorder(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs8),
          child: Text(strings.orSeparator,
              style:
                  AppTextStyles.labelMd.copyWith(color: AppColors.textMuted)),
        ),
        Wrap(
          spacing: AppSpacing.xs8,
          children: [
            for (var i = 0; i < areas.length; i++)
              ChoiceChip(
                label: Text(areas[i]),
                selected: areaIndex == i,
                onSelected: (_) => onAreaSelected(i),
              ),
          ],
        ),
      ],
    );
  }
}

class _PickupDetails extends ConsumerWidget {
  const _PickupDetails({required this.strings});

  final CheckoutStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timing = ref.watch(checkoutDraftProvider).pickupTiming;
    final slots = upcomingPickupSlots(DateTime.now().toUtc());

    return Wrap(
      spacing: AppSpacing.xs8,
      runSpacing: AppSpacing.xs8,
      children: [
        ChoiceChip(
          label: Text(strings.slotNow),
          selected: timing?.isNow ?? true,
          onSelected: (_) => ref
              .read(checkoutDraftProvider.notifier)
              .setPickupTiming(const PickupTiming.now()),
        ),
        for (final slot in slots)
          ChoiceChip(
            label: Text(slot.label),
            selected:
                !(timing?.isNow ?? true) && timing?.slotUtc == slot.startUtc,
            onSelected: (_) => ref
                .read(checkoutDraftProvider.notifier)
                .setPickupTiming(PickupTiming.slot(slot.startUtc)),
          ),
      ],
    );
  }
}

class _DeliveryDetails extends ConsumerWidget {
  const _DeliveryDetails({
    required this.strings,
    required this.textController,
    required this.newLabel,
    required this.onNewLabel,
    required this.showForm,
    required this.onToggleForm,
    required this.saving,
    required this.onSave,
  });

  final CheckoutStrings strings;
  final TextEditingController textController;
  final AddressLabel newLabel;
  final ValueChanged<AddressLabel> onNewLabel;
  final bool showForm;
  final VoidCallback onToggleForm;
  final bool saving;
  final VoidCallback onSave;

  String _labelName(AppLang lang, AddressLabel label) => switch (label) {
        AddressLabel.home => strings.labelHome,
        AddressLabel.work => strings.labelWork,
        AddressLabel.other => strings.labelOther,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final auth = ref.watch(authControllerProvider);
    final googleUserId = auth.googleUser?.id ?? '';
    final addressesAsync = ref.watch(addressesProvider(googleUserId));
    final draftAddressId = ref.watch(checkoutDraftProvider).addressId;
    final labels = {
      for (final label in AddressLabel.values) label: _labelName(lang, label),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        addressesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xs8),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => Text(
            strings.noAddressesLine,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
          ),
          data: (addresses) => addresses.isEmpty
              ? Text(
                  strings.noAddressesLine,
                  style:
                      AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(strings.savedAddressesLabel,
                        style: AppTextStyles.labelMd
                            .copyWith(color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs8),
                    for (final address in addresses)
                      _AddressOption(
                        selected: draftAddressId == address.id,
                        title: '${labels[address.label]} · ${address.addressText}',
                        onTap: () => ref
                            .read(checkoutDraftProvider.notifier)
                            .setAddressId(address.id),
                      ),
                  ],
                ),
        ),
        if (!showForm)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onToggleForm,
              child: Text(strings.addAddressTitle),
            ),
          )
        else ...[
          const SizedBox(height: AppSpacing.xs8),
          Wrap(
            spacing: AppSpacing.xs8,
            children: [
              for (final entry in labels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: newLabel == entry.key,
                  onSelected: (_) => onNewLabel(entry.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs8),
          TextField(
            controller: textController,
            decoration: InputDecoration(
              labelText: strings.addressLineLabel,
              hintText: strings.addressLineHint,
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.xs8),
          FilledButton.tonal(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.addAddressCta),
          ),
        ],
      ],
    );
  }
}

class _AddressOption extends StatelessWidget {
  const _AddressOption({
    required this.selected,
    required this.title,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Flat selectable row (border only, no shadow): nested cards inside the
    // mode-details card would double the chrome.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs8),
      child: Material(
        color: selected ? AppColors.primaryFixedTint : AppColors.paperWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md8),
          side: BorderSide(
            color: selected
                ? AppColors.primary
                : AppColors.outline.withValues(alpha: 0.25),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.strings,
    required this.subtotalEgp,
    required this.feeEgp,
    required this.totalEgp,
    required this.isDelivery,
  });

  final CheckoutStrings strings;
  final int subtotalEgp;
  final int feeEgp;
  final int totalEgp;
  final bool isDelivery;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TotalsRow(label: strings.subtotalRow, value: strings.egp(subtotalEgp)),
            if (isDelivery) ...[
              const SizedBox(height: AppSpacing.xs8),
              _TotalsRow(
                label: strings.deliveryFeeRow,
                value: strings.egp(feeEgp),
              ),
            ],
            const Divider(),
            _TotalsRow(
              label: strings.totalRow,
              value: strings.egp(totalEgp),
              emphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? AppTextStyles.titleSm
        : AppTextStyles.bodyLg;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}

class _LoyaltyBanner extends StatelessWidget {
  const _LoyaltyBanner({
    required this.strings,
    required this.points,
    required this.redemption,
    required this.redeemed,
    required this.remainingPoints,
    required this.onToggleRedeem,
  });

  final CheckoutStrings strings;

  /// Earn preview for this order (after redemption discount).
  final int points;

  /// Affordable reward, or null when nothing applies (toggle hidden).
  final Redemption? redemption;
  final bool redeemed;
  final int remainingPoints;
  final ValueChanged<bool?>? onToggleRedeem;

  @override
  Widget build(BuildContext context) {
    final redemption = this.redemption;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm16),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(AppRadii.md8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('☕', style: TextStyle(fontSize: 22)),
              const SizedBox(width: AppSpacing.xs8),
              Expanded(
                child: Text(
                  strings.loyaltyBanner(points),
                  style:
                      AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (redemption != null) ...[
            const SizedBox(height: AppSpacing.xs8),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md8),
              onTap: onToggleRedeem == null
                  ? null
                  : () => onToggleRedeem!(!redeemed),
              child: Row(
                children: [
                  Checkbox(
                    value: redeemed,
                    onChanged: onToggleRedeem,
                  ),
                  Expanded(
                    child: Text(
                      strings.redeemToggle(
                        redemption.costPts,
                        strings.redemptionLabel(redemption.type),
                      ),
                      style: AppTextStyles.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (redeemed)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.lg32),
                child: Text(
                  strings.redeemRemaining(remainingPoints),
                  style: AppTextStyles.bodySm
                      .copyWith(color: AppColors.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.label,
    required this.totalEgp,
    required this.strings,
    required this.busy,
    required this.onSubmit,
  });

  final String label;
  final int totalEgp;
  final CheckoutStrings strings;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        boxShadow: AppShadows.coffeeShadows(
          offset: const Offset(0, -4),
          blurRadius: 12,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.margin20,
        AppSpacing.sm16,
        AppSpacing.margin20,
        AppSpacing.md24,
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          onPressed: busy ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('$label · ${strings.egp(totalEgp)}'),
        ),
      ),
    );
  }
}
