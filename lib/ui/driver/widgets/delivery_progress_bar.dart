// Horizontal three-step delivery progress (#014, FEATURES §7):
// تم القبول ← استلمت من الكافيه ← تم التوصيل. [completedCount] is how many
// steps are done (0..3); done steps fill deep-forest, the current frontier
// pulses orange, future steps stay outlined. Labels are pre-localized.
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class DeliveryProgressBar extends StatelessWidget {
  const DeliveryProgressBar({
    super.key,
    required this.labels,
    required this.completedCount,
  });

  /// Exactly three labels: accepted / picked up / delivered.
  final List<String> labels;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    assert(labels.length == 3);
    final clamped = completedCount.clamp(0, 3);
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: i < clamped
                    ? AppColors.primary
                    : AppColors.outline.withValues(alpha: 0.35),
              ),
            ),
          _StepDot(
            label: labels[i],
            state: i < clamped
                ? _StepState.done
                : (i == clamped ? _StepState.current : _StepState.upcoming),
            index: i,
          ),
        ],
      ],
    );
  }
}

enum _StepState { done, current, upcoming }

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.label,
    required this.state,
    required this.index,
  });

  final String label;
  final _StepState state;
  final int index;

  static const _icons = [
    Icons.task_alt_outlined, // accepted
    Icons.takeout_dining_outlined, // picked up from café
    Icons.celebration_outlined, // delivered
  ];

  Color get _fill => switch (state) {
    _StepState.done => AppColors.primary,
    _StepState.current => AppColors.secondaryContainer,
    _StepState.upcoming => Colors.transparent,
  };

  Color get _iconColor => switch (state) {
    _StepState.done || _StepState.current => Colors.white,
    _StepState.upcoming => AppColors.outline,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _fill,
            border: Border.all(
              color: state == _StepState.upcoming
                  ? AppColors.outline.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(_icons[index], size: 20, color: _iconColor),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelMd.copyWith(
              fontWeight: state == _StepState.upcoming
                  ? FontWeight.w400
                  : FontWeight.w700,
              color: state == _StepState.upcoming
                   ? AppColors.textMuted
                   : AppColors.coffeeBean,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
