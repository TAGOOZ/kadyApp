// Driver card (#006): shown on delivery orders once the status reaches
// في الطريق إليك and a driver is assigned. v1 shows a placeholder name —
// real driver profiles land with #007; call + directions are MVP
// snackbars (no url_launcher dependency).
import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_orders.dart';
import '../../../core/theme/app_theme.dart';

class DriverCard extends StatelessWidget {
  const DriverCard({
    super.key,
    required this.onCallTap,
    required this.onDirectionsTap,
    this.driverName,
  });

  final VoidCallback onCallTap;
  final VoidCallback onDirectionsTap;

  /// Real name when available later; null renders the placeholder.
  final String? driverName;

  @override
  Widget build(BuildContext context) {
    final strings = OrdersStringsCatalog.of(AppLang.ar);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.driverLabel, style: AppTextStyles.titleMd),
            const SizedBox(height: AppSpacing.sm16),
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.parchment,
                  child: const Icon(Icons.person_outline,
                      color: AppColors.coffeeBean),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    driverName ?? strings.driverNamePlaceholder,
                    style: AppTextStyles.bodyLg
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                // Phone row tap → snackbar (tel: launch is out of scope).
                IconButton(
                  tooltip: strings.callSoonSnackbar,
                  onPressed: onCallTap,
                  icon: const Icon(Icons.phone_outlined,
                      color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm16),
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.parchment,
                borderRadius: BorderRadius.circular(AppRadii.md8),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, color: AppColors.outline),
                  const SizedBox(height: AppSpacing.xs8),
                  Text(
                    strings.mapHint,
                    style:
                        AppTextStyles.bodySm.copyWith(color: AppColors.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm16),
            OutlinedButton.icon(
              onPressed: onDirectionsTap,
              icon: const Icon(Icons.directions_outlined),
              label: Text(strings.directionsCta),
            ),
          ],
        ),
      ),
    );
  }
}
