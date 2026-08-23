// Colored status pill for the staff board (#012): one color per DB status
// vocabulary entry, label pre-localized by the caller (pure layer has no
// strings access — same pattern as the customer timeline).
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/order_status_flow.dart';

abstract final class StaffStatusColors {
  /// جديد orange (needs action) · مقبول deep green · قيد التحضير coffee brown
  /// · جاهز parchment-on-green · خرج للتوصيل burnt · تم التسليم muted
  /// · مُلغي red.
  static Color of(OrderWireStatus status) => switch (status) {
        OrderWireStatus.received => AppColors.secondary,
        OrderWireStatus.accepted => AppColors.primary,
        OrderWireStatus.inPrep => AppColors.coffeeBean,
        OrderWireStatus.ready => const Color(0xFF156B41),
        // #9E3900 keeps the burnt-orange identity and clears 4.5:1 on its own
        // 12% tint; secondaryContainer (#FF7434) measured only 2.3:1 as text.
        OrderWireStatus.outForDelivery => const Color(0xFF9E3900),
        OrderWireStatus.done => AppColors.textMuted,
        OrderWireStatus.cancelled => AppColors.error,
      };
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    required this.label,
  });

  final OrderWireStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = StaffStatusColors.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelMd.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
