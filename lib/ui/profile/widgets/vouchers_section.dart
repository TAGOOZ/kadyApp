// Vouchers section (#011): active rewards from loyaltyProvider.state —
// free drink / topping / snack cards with a صالحة status chip, plus an
// empty state nudging the games hub.
import 'package:flutter/material.dart';

import '../../../core/l10n/strings_profile.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/loyalty_controller.dart';

class VouchersSection extends StatelessWidget {
  const VouchersSection({
    super.key,
    required this.vouchers,
    required this.strings,
  });

  final List<Voucher> vouchers;
  final ProfileStrings strings;

  @override
  Widget build(BuildContext context) {
    if (vouchers.isEmpty) {
      return Row(
        children: [
          const Icon(Icons.redeem_outlined,
              size: 20, color: AppColors.outline),
          const SizedBox(width: AppSpacing.xs8),
          Expanded(
            child: Text(
              strings.vouchersEmpty,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        for (var i = 0; i < vouchers.length; i++) ...[
          if (i > 0) const Divider(),
          _VoucherCard(voucher: vouchers[i], strings: strings),
        ],
      ],
    );
  }
}

class _VoucherCard extends StatelessWidget {
  const _VoucherCard({required this.voucher, required this.strings});

  final Voucher voucher;
  final ProfileStrings strings;

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = switch (voucher.type) {
      VoucherType.freeDrink => (Icons.local_cafe_rounded, AppColors.primaryFixedTint),
      VoucherType.freeTopping => (Icons.icecream_rounded, AppColors.voucherTopping),
      VoucherType.freeSnack => (Icons.cookie_rounded, AppColors.parchment),
    };
    final isExpired = voucher.isExpired;
    final isSoon = voucher.isExpiringSoon;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isExpired ? AppColors.outline.withValues(alpha: 0.3) : tint,
            borderRadius:
                const BorderRadius.all(Radius.circular(AppRadii.md8)),
          ),
          child: Icon(icon,
              size: 22,
              color: isExpired ? AppColors.textMuted : AppColors.primaryContainer),
        ),
        const SizedBox(width: AppSpacing.sm16 - 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.voucherLabel(voucher.type),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyLg.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isExpired ? AppColors.textMuted : null,
                  decoration: isExpired ? TextDecoration.lineThrough : null,
                ),
              ),
              if (voucher.expiresAt != null)
                Text(
                  isExpired
                      ? strings.voucherExpiredChip
                      : strings.voucherExpiryLabel(voucher.expiresAt!),
                  style: AppTextStyles.labelMd.copyWith(
                    color: isExpired
                        ? AppColors.error
                        : isSoon
                            ? AppColors.secondary
                            : AppColors.textMuted,
                    fontWeight: isSoon ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isExpired ? AppColors.outline.withValues(alpha: 0.2) : AppColors.primaryFixedTint,
            borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
          ),
          child: Text(
            isExpired ? strings.voucherExpiredChip : strings.voucherValidChip,
            style: AppTextStyles.labelMd.copyWith(
              fontWeight: FontWeight.w700,
              color: isExpired ? AppColors.textMuted : AppColors.primaryContainer,
            ),
          ),
        ),
      ],
    );
  }
}
