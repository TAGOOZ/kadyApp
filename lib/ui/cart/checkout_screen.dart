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
import 'package:uuid/uuid.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_checkout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/device/device_id_provider.dart';
import '../../data/repos/orders_repository.dart';
import '../../domain/auth_controller.dart';
import '../../domain/cart_controller.dart';
import '../../domain/loyalty_controller.dart';
import '../../domain/loyalty_rules.dart';
import '../auth/guest_save_prompt.dart';
import 'widgets/loyalty_banner.dart';
import 'widgets/mode_details_card.dart';
import 'widgets/submit_bar.dart';
import 'widgets/totals_card.dart';

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
  String? _pendingIdempotencyKey; // RISK-04: hold for retry idempotency (#1)

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
          await ref.read(ordersRepoProvider).saveAddress(SavedAddressInput(
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
    // RISK-03/RISK-04: device signal (untrusted, nullable, never required) + idempotency.
    // Device: non-blocking read so widget tests without SharedPreferences mock don't hang.
    // Real app: deviceIdFutureProvider loads from SharedPreferences; if still loading, send null (signal not proof).
    // Documented trade-off: first order after cold start may miss device signal; next order will have it.
    String? deviceId;
    try {
      deviceId = ref.read(deviceIdProvider);
    } catch (_) {
      try {
        deviceId = ref.read(deviceIdFutureProvider).asData?.value;
        if (deviceId != null && deviceId.isEmpty) deviceId = null;
      } catch (_) {
        deviceId = null;
      }
    }
    // Idempotency: generate once per submit and hold for retry (fixes #1). Reused if retry within debounce.
    final idempotencyKey = _pendingIdempotencyKey ??= const Uuid().v4();
    try {
      final placed = await ref.read(ordersRepoProvider).placeOrder(NewOrder(
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
            deviceId: deviceId,
            idempotencyKey: idempotencyKey,
          ));
      // RISK-04: loyalty gate — server trigger suppresses credit while held for verification
      // (WHEN risk_action = 'approved'). Client respects gate without trusting client.
      final needsVerification = placed.needsVerification;
      final isRejected = placed.isRejected;
      if (isRejected) {
        // Rejected is terminal — keep debounce so user can't spam, but clear idempotency immediately
        // so a retry with a smaller cart total gets a fresh key and fresh risk evaluation (#3).
        _pendingIdempotencyKey = null;
        _unlockTimer?.cancel();
        _locked = true;
        _unlockTimer = Timer(_debounce, () {
          if (mounted) setState(() => _locked = false);
        });
        if (mounted) _showError(s, s.orderRejected);
        return;
      }
      if (!needsVerification) {
        // Real earn path (#007): server trigger is authoritative (migration 0004),
        // client credit is now awaited to avoid lost-update/double-earn race
        // (CORRECTNESS-05). Navigation waits for the idempotent credit.
        await ref.read(loyaltyProvider.notifier).creditProcessedOrder(
              orderId: placed.id,
              subtotalEgp: subtotalEgp,
              dineIn: mode == OrderMode.dineIn,
              redemption: redemption,
            );
      }
      // Success path: arm debounce and clear pending key on next order
      _unlockTimer?.cancel();
      _locked = true;
      _pendingIdempotencyKey = null; // success clears key; next order gets fresh UUID
      _unlockTimer = Timer(_debounce, () {
        if (mounted) setState(() => _locked = false);
      });
      if (!mounted) return;
      if (needsVerification) {
        // Branch to order status with verification banner instead of normal confirmation
        context.pushReplacement('/orders/${placed.id}');
      } else {
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
      }
      notifier.reset();
    } catch (_) {
      // Standard error policy: snackbar + form preserved for retry; keep pending key for idempotent retry (#1).
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

    // Clear pending idempotency when cart mutates so retry with new total gets fresh evaluation (#3).
    ref.listen(cartProvider, (prev, next) {
      if (prev != null && (prev.length != next.length || prev.toString() != next.toString())) {
        _pendingIdempotencyKey = null;
      }
    });

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
                ModeDetailsCard(
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
                TotalsCard(
                  strings: s,
                  subtotalEgp: subtotalAfterRedemption,
                  feeEgp: fee,
                  totalEgp: total,
                  isDelivery: mode == OrderMode.delivery,
                ),
                const SizedBox(height: AppSpacing.sm16),
                LoyaltyBanner(
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
          SubmitBar(
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
