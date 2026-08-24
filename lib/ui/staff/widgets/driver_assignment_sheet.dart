// Driver handover picker — staff selects which driver takes a delivery.
// Fetches eligible drivers via `staffDriversProvider` (profiles where role=driver).
// Returns the selected `user_id` via Navigator.pop, or null on dismiss.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_staff.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/staff_orders_repository.dart';

class DriverAssignmentSheet extends ConsumerStatefulWidget {
  const DriverAssignmentSheet({super.key, required this.lang});

  final AppLang lang;

  @override
  ConsumerState<DriverAssignmentSheet> createState() =>
      _DriverAssignmentSheetState();
}

class _DriverAssignmentSheetState extends ConsumerState<DriverAssignmentSheet> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final strings = StaffStrings.of(widget.lang);
    final driversAsync = ref.watch(staffDriversProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.assignDriverTitle, style: AppTextStyles.titleMd),
              const SizedBox(height: AppSpacing.xs8),
              Text(
                strings.assignDriverHint,
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.sm16),
              Flexible(
                child: driversAsync.when(
                  data: (drivers) {
                    if (drivers.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            strings.noDrivers,
                            style: AppTextStyles.bodyLg
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: drivers.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final d = drivers[index];
                        final title = (d.displayName?.trim().isNotEmpty == true)
                            ? d.displayName!.trim()
                            : d.userId.substring(0, 8);
                        final selected = _selectedId == d.userId;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.parchment,
                            child: Text(
                              title.characters.first.toUpperCase(),
                              style: AppTextStyles.labelMd
                                  .copyWith(color: AppColors.coffeeBean),
                            ),
                          ),
                          title: Text(title, style: AppTextStyles.bodyLg),
                          subtitle: Text(
                            d.userId.substring(0, 8),
                            style: AppTextStyles.bodySm
                                .copyWith(color: AppColors.textMuted),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle,
                                  color: AppColors.coffeeBean)
                              : const Icon(Icons.circle_outlined,
                                  color: AppColors.outline),
                          onTap: () =>
                              setState(() => _selectedId = d.userId),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Text(
                          StaffStrings.of(widget.lang).errorGeneric,
                          style: AppTextStyles.bodyLg
                              .copyWith(color: AppColors.error),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => ref.invalidate(staffDriversProvider),
                          child: Text(StaffStrings.of(widget.lang).retryCta),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selectedId == null
                      ? null
                      : () => Navigator.of(context).pop(_selectedId),
                  child: Text(strings.confirmAssignment),
                ),
              ),
              const SizedBox(height: AppSpacing.xs8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper to open the sheet and await the selected driver id.
Future<String?> showDriverAssignmentSheet(
  BuildContext context,
  AppLang lang,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DriverAssignmentSheet(lang: lang),
  );
}
