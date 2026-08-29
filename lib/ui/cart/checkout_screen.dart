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
import '../../core/device/device_id_provider.dart';
import '../../data/repos/orders_repository.dart';
import '../../domain/auth_controller.dart';
import '../../domain/cart_controller.dart';
import '../../domain/loyalty_controller.dart';
import '../../domain/loyalty_rules.dart';
import '../../domain/pricing.dart';
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
    final timing = draftState.pickupTiming;
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
    // Sanitize notes to strip HTML tags (XSS defense: <script> is not executed
    // via Flutter Text but we fully strip tags so persisted jsonb is clean).
    String sanitizeNote(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final draftNotes = sanitizeNote(draftState.notes);
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
    // Deep Intake: no Uuid.v4 nonce — content-addressed key
    // (phone + items + address) is computed in OrdersRepo/domain
    // order_intake and server pipeline. Debounce remains for UX only.
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
            pickupSlotUtc:
                timing == null || timing.isNow ? null : timing.slotUtc,
            addressId: candidate.addressId,
            notes: notes.isEmpty ? null : notes,
            deviceId: deviceId,
          ));
      // RISK-04: loyalty gate — server trigger suppresses credit while held for verification
      // (WHEN risk_action = 'approved'). Client respects gate without trusting client.
      final needsVerification = placed.needsVerification;
      final isRejected = placed.isRejected;
      if (isRejected) {
        _unlockTimer?.cancel();
        _locked = true;
        _unlockTimer = Timer(_debounce, () {
          if (mounted) setState(() => _locked = false);
        });
        if (mounted) _showError(s, s.orderRejected);
        return;
      }
      // Server-authoritative loyalty: Postgres trigger credit_new_order owns all
      // Points/Stamps crediting (AGENTS #4). Client only previews (earnedFor/redeemable)
      // and resyncs via loyalty watch/refreshFor. No client creditProcessedOrder — deleted dual writer.
      // Fire-and-forget refresh so confirmation/profile show updated balance even if Realtime lags/offline.
      // ignore: unawaited_futures
      ref.read(loyaltyProvider.notifier).refreshFor(googleUserId).catchError((_) {});
      _unlockTimer?.cancel();
      _locked = true;
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

    final configuredFee =
        ref.watch(deliveryFeeProvider).asData?.value ?? defaultDeliveryFeeEgp;
    // Pricing deep module owns fee/total/earn — single source for preview == server.
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
    // Build Pricing seam input (avoids cart_controller→pricing cycle via mapping).
    final pricingLines = [
      for (final l in lines)
        PricingCartLine(item: l.item, config: l.config, qty: l.qty),
    ];
    final quote = pricingQuote(
      lines: pricingLines,
      isDelivery: mode == OrderMode.delivery,
      isDineIn: mode == OrderMode.dineIn,
      configuredDeliveryFeeEgp: configuredFee,
      loyaltyConfig: rulesConfig,
      redemption: redeemed ? redemption : null,
      doubleWindow: loyalty.doubleNextOrder,
    );
    final subtotalAfterRedemption = quote.subtotalEgp;
    final fee = quote.deliveryFeeEgp;
    final total = quote.totalEgp;
    final points = quote.earnedPreview;

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
                    _validationError = null;
                    ref
                        .read(checkoutDraftProvider.notifier)
                        .setTableArea(value);
                  }),
                  onAreaSelected: (index) {
                    _tableController.clear();
                    ref
                        .read(checkoutDraftProvider.notifier)
                        .setTableArea(index == 0 ? s.areaInside : s.areaTerrace);
                    setState(() {
                      _areaIndex = index;
                      _validationError = null;
                    });
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
                  onAddressSelected: () =>
                      setState(() => _validationError = null),
                  onPickupTimingSelected: () =>
                      setState(() => _validationError = null),
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
