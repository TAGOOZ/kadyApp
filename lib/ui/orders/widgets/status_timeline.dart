// Vertical status timeline (#006, FEATURES §3.6): icon + label + timestamp
// per step, pulsing highlight on the active step (AnimationController) and
// a thin connector line that fills between completed steps. Cancelled
// orders render a red terminal row instead of any step progress.
import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_orders.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/order_status_flow.dart';

class StatusTimeline extends StatefulWidget {
  const StatusTimeline({
    super.key,
    required this.steps,
    required this.currentIndex,
    required this.timestamps,
    required this.pulse,
    this.lang = AppLang.ar,
    this.cancelled = false,
    this.cancelledLabel = 'مُلغي',
    this.cancelReasonPrefix = '',
    this.rejectReason,
  });

  /// Mode steps from [OrderStatusFlow.stepsFor].
  final List<FlowStep> steps;

  /// Index of the current step; -1 when cancelled/unknown.
  final int currentIndex;

  /// Timestamp per step index (already resolved against order_events with
  /// created_at fallback); null renders no time yet.
  final List<DateTime?> timestamps;

  /// Repeating pulse animation (0..1); driven by the parent screen so a
  /// single controller animates the whole timeline.
  final Animation<double> pulse;

  /// Picks labelAr vs labelEn from [FlowStep]; defaults to ar.
  final AppLang lang;
  final bool cancelled;
  final String cancelledLabel;
  final String cancelReasonPrefix;
  final String? rejectReason;

  @override
  State<StatusTimeline> createState() => _StatusTimelineState();
}

class _StatusTimelineState extends State<StatusTimeline> {
  static const _rowGap = 28.0;

  bool _isDone(int index) =>
      !widget.cancelled && index <= widget.currentIndex && widget.currentIndex >= 0;

  bool _isActive(int index) => !widget.cancelled && index == widget.currentIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.steps.length; i++) ...[
          _StepRow(
            step: widget.steps[i],
            state: _isActive(i)
                ? _StepState.active
                : _isDone(i)
                    ? _StepState.done
                    : _StepState.upcoming,
            timestamp: i < widget.timestamps.length ? widget.timestamps[i] : null,
            pulse: widget.pulse,
            showConnector: i < widget.steps.length - 1,
            // Fill only up TO the active step, never past it.
            connectorFilled: !widget.cancelled &&
                widget.currentIndex >= 0 &&
                i < widget.currentIndex,
            lang: widget.lang,
          ),
          if (i < widget.steps.length - 1)
            const SizedBox(height: _rowGap - 12),
        ],
        if (widget.cancelled) ...[
          const SizedBox(height: _rowGap),
          _CancelledRow(
            label: widget.cancelledLabel,
            reason: widget.rejectReason,
            reasonPrefix: widget.cancelReasonPrefix,
          ),
        ],
      ],
    );
  }
}

enum _StepState { done, active, upcoming }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.state,
    required this.timestamp,
    required this.pulse,
    required this.showConnector,
    required this.connectorFilled,
    required this.lang,
  });

  final FlowStep step;
  final _StepState state;
  final DateTime? timestamp;
  final Animation<double> pulse;
  final bool showConnector;
  final bool connectorFilled;
  final AppLang lang;

  String get label => lang == AppLang.ar ? step.labelAr : step.labelEn;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _StepState.done || _StepState.active => AppColors.primary,
      _StepState.upcoming => AppColors.outline,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                _StepCircle(
                  icon: step.icon,
                  color: color,
                  filled: state != _StepState.upcoming,
                  pulse: state == _StepState.active ? pulse : null,
                ),
                if (showConnector)
                  Expanded(child: _Connector(filled: connectorFilled)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.bodyLg.copyWith(
                        fontWeight: state == _StepState.upcoming
                            ? FontWeight.w400
                            : FontWeight.w700,
                        color: state == _StepState.upcoming
                            ? AppColors.textMuted
                            : AppColors.coffeeBean,
                      ),
                    ),
                  ),
                  if (timestamp != null)
                    Text(
                      OrdersStrings.hhmmOf(timestamp!),
                      style: AppTextStyles.bodySm.copyWith(
                         color: AppColors.textMuted,
                       ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({
    required this.icon,
    required this.color,
    required this.filled,
    required this.pulse,
  });

  final IconData icon;
  final Color color;
  final bool filled;
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    Widget circle = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(icon, size: 20, color: filled ? Colors.white : color),
    );

    final pulseAnimation = pulse;
    if (pulseAnimation == null) return circle;

    // Active step: soft halo breathing with the shared controller.
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        final t = pulseAnimation.value;
        return Container(
          width: 40 + 10 * t,
          height: 40 + 10 * t,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.18 * (1 - t)),
          ),
          alignment: Alignment.center,
          child: child,
        );
      },
      child: circle,
    );
  }
}

/// Thin vertical line between consecutive circles; fills solid once the
/// upper step is reached.
class _Connector extends StatelessWidget {
  const _Connector({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 3,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.sm4),
          color: filled ? AppColors.primary : AppColors.outline.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _CancelledRow extends StatelessWidget {
  const _CancelledRow({
    required this.label,
    required this.reason,
    required this.reasonPrefix,
  });

  final String label;
  final String? reason;
  final String reasonPrefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cancel_outlined, color: AppColors.error, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.titleMd.copyWith(color: AppColors.error),
              ),
            ],
          ),
          if (reason != null && reason!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '$reasonPrefix: $reason',
              style:
                  AppTextStyles.bodySm.copyWith(color: AppColors.coffeeBean),
            ),
          ],
        ],
      ),
    );
  }
}
