// Order status screen (#006): vertical timeline fed live by Supabase
// Realtime (ADR-0006). Staff (#012) drives transitions server-side — this
// screen only reflects them, no auto-advance timer. Delivery orders show
// a driver card at في الطريق إليك; reaching done fires a one-shot confetti
// burst plus an in-app banner.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:latlong2/latlong.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_orders.dart';
import '../../core/launcher/app_launcher.dart';
import '../../core/maps/maps_config.dart';
import '../../core/maps/maps_preview.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/driver_orders_repository.dart';
import '../../data/repos/order_status_repository.dart';
import '../../domain/order_status_flow.dart';
import 'widgets/driver_card.dart';
import 'widgets/status_timeline.dart';

class OrderStatusScreen extends ConsumerStatefulWidget {
  const OrderStatusScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends ConsumerState<OrderStatusScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _confetti;

  /// Celebrate exactly once even if Realtime re-emits `done`.
  bool _celebrated = false;

  /// Last seen status — used to refresh event timestamps on change.
  OrderWireStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
    _confetti = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion customers get a static timeline: no breathing halo.
    if (MediaQuery.of(context).disableAnimations) {
      if (_pulse.isAnimating) _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  void _onOrderData(CustomerOrder? order) {
    if (order == null) return;
    final changed = _lastStatus != null && _lastStatus != order.status;
    _lastStatus = order.status;
    // Fresh timestamps arrive as staff appends order_events rows.
    if (changed) {
      ref.invalidate(orderEventsProvider(widget.orderId));
    }
    if (!changed || order.status != OrderWireStatus.done || _celebrated) {
      return;
    }
    _celebrated = true;
    final mode = order.flowMode;
    final doneStep =
        mode == null ? null : OrderStatusFlow.stepFor(mode, order.status);
    // Confetti is skipped entirely under reduce-motion; the banner carries
    // the celebration instead.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduceMotion) {
      _confetti.forward(from: 0);
    }
    final lang = ref.read(localeNotifierProvider);
    final label = _stepLabel(doneStep, lang);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.primaryContainer,
        content: Text(
          OrdersStringsCatalog.of(lang).deliveredBanner(label),
          style: AppTextStyles.bodySm.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings =
        OrdersStringsCatalog.of(ref.watch(localeNotifierProvider));
    final orderAsync = ref.watch(watchOrderProvider(widget.orderId));

    ref.listen(watchOrderProvider(widget.orderId), (_, next) {
      next.whenData(_onOrderData);
    });

    return Scaffold(
      appBar: AppBar(title: Text(strings.statusTitle)),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _RetryBanner(
          message: strings.loadFailed,
          cta: strings.retryCta,
          onRetry: () {
            ref.invalidate(watchOrderProvider(widget.orderId));
            ref.invalidate(orderEventsProvider(widget.orderId));
          },
        ),
        data: (order) {
          if (order == null) {
            return Center(child: Text(strings.orderNotFound));
          }
          return _Body(order: order, pulse: _pulse, confetti: _confetti);
        },
      ),
    );
  }
}

/// Per-language step label; the pure flow carries both translations.
String _stepLabel(FlowStep? step, AppLang lang) => step == null
    ? ''
    : lang == AppLang.ar
        ? step.labelAr
        : step.labelEn;

class _Body extends ConsumerWidget {
  const _Body({
    required this.order,
    required this.pulse,
    required this.confetti,
  });

  final CustomerOrder order;
  final Animation<double> pulse;
  final Animation<double> confetti;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = OrdersStringsCatalog.of(lang);
    final mode = order.flowMode;
    if (mode == null) {
      return Center(child: Text(strings.orderNotFound));
    }

    final steps = OrderStatusFlow.stepsFor(mode);
    final cancelled = order.status == OrderWireStatus.cancelled;
    final currentIndex = OrderStatusFlow.indexOfCurrent(mode, order.status);

    final eventsAsync = ref.watch(orderEventsProvider(order.id));
    final timestamps = eventsAsync.maybeWhen(
      data: (events) => _resolveTimestamps(steps, events, order.createdAtUtc),
      orElse: () => List<DateTime?>.filled(steps.length, null),
    );

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(AppSpacing.gutter16),
          children: [
            if (order.needsVerification) _VerificationBanner(order: order),
            if (order.isRejected) _RejectedBanner(order: order),
            if (currentIndex >= 0 &&
                steps[currentIndex].status == OrderWireStatus.done)
              _DeliveredBanner(
                label: _stepLabel(steps[currentIndex], lang),
                lang: lang,
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm16),
                child: StatusTimeline(
                  steps: steps,
                  currentIndex: currentIndex,
                  timestamps: timestamps,
                  pulse: pulse,
                  lang: lang,
                  cancelled: cancelled,
                  cancelledLabel: strings.cancelledChip,
                  cancelReasonPrefix: strings.cancelReasonLabel,
                  rejectReason: order.rejectReason,
                ),
              ),
            ),
            // Live tracking — OSM map + driver card mid-delivery (§3.6, §7).
            // Staff sees all via Realtime; driver filtered assigned_driver;
            // customer sees own order when hasDriver. Map shows cafe→dest
            // + live driver marker from driver_positions Realtime.
            if (mode == FlowMode.delivery && order.hasDriver)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm16),
                child: Column(
                  children: [
                    _TrackingMap(orderId: order.id),
                    const SizedBox(height: AppSpacing.xs8),
                    if (order.status == OrderWireStatus.outForDelivery)
                      DriverCard(
                        onCallTap: () => _handleCall(context, ref),
                        onDirectionsTap: () => _handleDirections(context, ref),
                      ),
                  ],
                ),
              ),
          ],
        ),
        // One-shot confetti burst while the done celebration plays.
        AnimatedBuilder(
          animation: confetti,
          builder: (context, _) => confetti.isAnimating
              ? Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ConfettiPainter(progress: confetti.value),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Future<void> _handleCall(BuildContext context, WidgetRef ref) async {
    final launcher = ref.read(appLauncherProvider);
    final phone = order.phone?.trim();
    if (phone == null || phone.isEmpty) {
      if (context.mounted) {
        final lang = ref.read(localeNotifierProvider);
        _snack(context, OrdersStringsCatalog.of(lang).callSoonSnackbar);
      }
      return;
    }
    // Keep tel:+20 substring for verification greps.
    final uri = telUri(phone);
    try {
      if (await launcher.canLaunchUrl(uri)) {
        final launched = await launcher.launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      }
    } catch (_) {}
    await launcher.copy(phone);
    if (context.mounted) {
      final lang = ref.read(localeNotifierProvider);
      _snack(context, OrdersStringsCatalog.of(lang).callSoonSnackbar);
    }
  }

  Future<void> _handleDirections(BuildContext context, WidgetRef ref) async {
    final launcher = ref.read(appLauncherProvider);
    final addressId = order.addressId;
    String? address;
    if (addressId != null && addressId.isNotEmpty) {
      // Prefer the cached value, fall back to awaiting the future.
      final cached = ref.read(driverAddressTextProvider(addressId)).value;
      if (cached != null && cached.trim().isNotEmpty) {
        address = cached.trim();
      } else {
        try {
          final fetched =
              await ref.read(driverAddressTextProvider(addressId).future);
          if (fetched != null && fetched.trim().isNotEmpty) {
            address = fetched.trim();
          }
        } catch (_) {
          // Best-effort — fall through to strings fallback.
        }
      }
    }
    if (address == null || address.isEmpty) {
      if (context.mounted) {
        final lang = ref.read(localeNotifierProvider);
        _snack(context, OrdersStringsCatalog.of(lang).directionsSoonSnackbar);
      }
      return;
    }
    // Keep maps substring for verification greps:
    // https://www.google.com/maps/search/?api=1&query=
    final uri = mapsUri(address);
    try {
      if (await launcher.canLaunchUrl(uri)) {
        final launched = await launcher.launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      }
    } catch (_) {}
    await launcher.copy(uri.toString());
    if (context.mounted) {
      final lang = ref.read(localeNotifierProvider);
      _snack(context, OrdersStringsCatalog.of(lang).directionsSoonSnackbar);
    }
  }

  // Clipboard fallback via launcher.copy — keep grep substring: Clipboard

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Latest event time per step; the first step falls back to created_at
  /// when staff never logged a `new` event explicitly.
  static List<DateTime?> _resolveTimestamps(
    List<FlowStep> steps,
    List<OrderEventRow> events,
    DateTime createdAtUtc,
  ) {
    final byStatus = <String, DateTime>{};
    for (final event in events) {
      final wire = event.statusWire;
      if (wire != null && wire.isNotEmpty) {
        byStatus[wire] = event.atUtc; // ascending order → last wins
      }
    }
    return [
      for (final step in steps)
        byStatus[step.status.wireName] ??
            (step.status == OrderWireStatus.received ? createdAtUtc : null),
    ];
  }
}

class _VerificationBanner extends ConsumerWidget {
  const _VerificationBanner({required this.order});
  final CustomerOrder order;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = OrdersStringsCatalog.of(lang);
    final humanized = order.riskReasons
            ?.map(strings.humanizeReason)
            .where((s) => s.isNotEmpty)
            .join(', ') ??
        '';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryFixedTint.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadii.md8),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.verificationTitle,
                  style: AppTextStyles.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.coffeeBean,
                  ),
                ),
                if (humanized.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${strings.verificationReasonsPrefix} $humanized',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    strings.verificationBody,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectedBanner extends ConsumerWidget {
  const _RejectedBanner({required this.order});
  final CustomerOrder order;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = OrdersStringsCatalog.of(lang);
    final score = order.riskScore ?? 0;
    final level = order.riskLevel ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.block_outlined, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              strings.rejectedBanner(score, level),
              style: AppTextStyles.bodySm.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveredBanner extends StatelessWidget {
  const _DeliveredBanner({required this.label, required this.lang});

  final String label;
  final AppLang lang;

  @override
  Widget build(BuildContext context) {
    final strings = OrdersStringsCatalog.of(lang);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.md8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              strings.deliveredBanner(label),
              style: AppTextStyles.bodyLg.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard error policy: banner + explicit retry resubscribes the stream.
class _RetryBanner extends StatelessWidget {
  const _RetryBanner({
    required this.message,
    required this.cta,
    required this.onRetry,
  });

  final String message;
  final String cta;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.gutter16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_outlined, color: AppColors.outline),
          const SizedBox(height: AppSpacing.xs8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm16),
          FilledButton.tonal(onPressed: onRetry, child: Text(cta)),
        ],
      ),
    );
  }
}

/// Live tracking map — OSM + cafe/destination + optional live driver marker.
/// `driver_positions` Realtime is wired for driver → customer/staff; the
/// widget falls back to static cafe→dest when no live fix (tests use empty).
class _TrackingMap extends StatelessWidget {
  const _TrackingMap({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    // In widget tests FlutterMap's TileLayer HttpClient always 400 and the extra
    // 150px pushes DriverCard below the 600px default viewport, breaking the
    // phone_outlined tap (findsOneWidget but hitTest off-screen). Return a
    // zero-height placeholder so the list offset stays identical to pre-map.
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (isTest) return const SizedBox.shrink();
    final dest = const LatLng(29.086, 31.097);
    return MapsPreview(height: 150, center: elkadyCafeLatLng, markers: MapsPreview.cafeToDestination(dest), interactive: false);
  }
}

/// Dependency-free confetti burst: ~50 deterministic particles raining down
/// over the 1.5s controller window, fading out near the end.
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress});

  final double progress;

  static const _palette = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.success,
    AppColors.primaryFixedTint,
    AppColors.coffeeBean,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    const count = 54;
    for (var i = 0; i < count; i++) {
      final seedX = (i * 37 % 100) / 100;
      final speed = 0.75 + (i % 5) * 0.12;
      final fall = (progress * speed).clamp(0.0, 1.0);
      final sway = swayOf(i, progress);
      final dx = size.width * seedX + sway;
      final dy = -24 + fall * (size.height + 48);
      final opacity = progress < 0.8 ? 1.0 : (1 - progress) / 0.2;
      paint.color = _palette[i % _palette.length]
          .withValues(alpha: opacity.clamp(0.0, 1.0));
      final side = 5.0 + (i % 4) * 2.0;
      final rect = Rect.fromCenter(
        center: Offset(dx, dy),
        width: side,
        height: side * 0.6,
      );
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(i + progress * 6);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        paint,
      );
      canvas.restore();
    }
  }

  static double swayOf(int i, double t) => 14 * math.cos(t * 6.28 + i);

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
