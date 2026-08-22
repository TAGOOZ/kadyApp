// Addresses section (#011): delivery targets from public.addresses —
// label chip (بيت/شغل/أخرى) + text + edit pencil, swipe-to-delete with an
// undo snackbar, and a dashed add button. Both open the shared edit sheet.
// Content-only: the screen supplies the card chrome and section title.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_profile.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/address.dart';

class AddressesSection extends StatelessWidget {
  const AddressesSection({
    super.key,
    required this.addresses,
    required this.strings,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AddressRecord> addresses;
  final ProfileStrings strings;
  final VoidCallback onAdd;
  final ValueChanged<AddressRecord> onEdit;

  /// Fired after the confirm step; the screen performs delete + undo.
  final ValueChanged<AddressRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < addresses.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs8),
          Dismissible(
            key: ValueKey('address_${addresses[i].id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: AlignmentDirectional.centerEnd,
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm16),
              decoration: const BoxDecoration(
                color: AppColors.error,
                borderRadius:
                    BorderRadius.all(Radius.circular(AppRadii.md8)),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            onDismissed: (_) => onDelete(addresses[i]),
            child: _AddressCard(
              address: addresses[i],
              strings: strings,
              onEdit: () => onEdit(addresses[i]),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs8),
        _AddAddressButton(label: strings.addAddressLabel, onTap: onAdd),
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.strings,
    required this.onEdit,
  });

  final AddressRecord address;
  final ProfileStrings strings;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm16 - 2),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.md8)),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primaryFixedTint.withValues(alpha: 0.6),
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadii.pill)),
            ),
            child: Text(
              strings.addressLabel(address.label),
              style: AppTextStyles.labelMd.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm16 - 4),
          Expanded(
            child: Text(
              address.addressText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySm,
            ),
          ),
          IconButton(
            tooltip: strings.editAddressTitle,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class _AddAddressButton extends StatelessWidget {
  const _AddAddressButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.md8)),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        // Dashed-border feel via a dotted underline-free outline: Flutter has
        // no native dashed Border, so we fake it with a custom painter.
        foregroundDecoration: const _DashedBorderDecoration(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 18),
            const SizedBox(width: AppSpacing.xs8 - 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMd.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight dashed rounded-rectangle border (no extra deps).
class _DashedBorderDecoration extends Decoration {
  const _DashedBorderDecoration();

  static const _dash = 5.0;
  static const _gap = 4.0;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      const _DashedBorderPainter();
}

class _DashedBorderPainter extends BoxPainter {
  const _DashedBorderPainter() : super(null);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size ?? Size.zero;
    final rect = offset & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      const Radius.circular(AppRadii.md8),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.outline.withValues(alpha: 0.7);

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _DashedBorderDecoration._dash)
            .clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _DashedBorderDecoration._gap;
      }
    }
  }
}
