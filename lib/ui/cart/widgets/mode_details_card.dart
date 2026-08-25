// Mode details card (ARCH-02 split): extracted from checkout_screen.dart.
// Handles dine-in / pickup / delivery sub-forms.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_checkout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repos/orders_repository.dart';
import '../../../domain/auth_controller.dart';

/// Saved delivery addresses for the signed-in customer.
final addressesProvider =
    FutureProvider.autoDispose.family<List<SavedAddress>, String>(
  (ref, googleUserId) =>
      ref.watch(ordersRepoProvider).fetchAddresses(googleUserId),
);

class ModeDetailsCard extends StatelessWidget {
  const ModeDetailsCard({
    super.key,
    required this.mode,
    required this.strings,
    required this.tableController,
    required this.areaIndex,
    required this.onTableChanged,
    required this.onAreaSelected,
    required this.addrTextController,
    required this.newAddrLabel,
    required this.onNewAddrLabelSelected,
    required this.showAddrForm,
    required this.onToggleAddrForm,
    required this.savingAddress,
    required this.onSaveAddress,
  });

  final OrderMode mode;
  final CheckoutStrings strings;
  final TextEditingController tableController;
  final int? areaIndex;
  final ValueChanged<String> onTableChanged;
  final ValueChanged<int?> onAreaSelected;
  final TextEditingController addrTextController;
  final AddressLabel newAddrLabel;
  final ValueChanged<AddressLabel> onNewAddrLabelSelected;
  final bool showAddrForm;
  final VoidCallback onToggleAddrForm;
  final bool savingAddress;
  final VoidCallback onSaveAddress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm16),
        child: switch (mode) {
          OrderMode.dineIn => DineInDetails(
              strings: strings,
              controller: tableController,
              areaIndex: areaIndex,
              onTableChanged: onTableChanged,
              onAreaSelected: onAreaSelected,
            ),
          OrderMode.pickup => PickupDetails(strings: strings),
          OrderMode.delivery => DeliveryDetails(
              strings: strings,
              textController: addrTextController,
              newLabel: newAddrLabel,
              onNewLabel: onNewAddrLabelSelected,
              showForm: showAddrForm,
              onToggleForm: onToggleAddrForm,
              saving: savingAddress,
              onSave: onSaveAddress,
            ),
        },
      ),
    );
  }
}

class DineInDetails extends StatelessWidget {
  const DineInDetails({
    super.key,
    required this.strings,
    required this.controller,
    required this.areaIndex,
    required this.onTableChanged,
    required this.onAreaSelected,
  });

  final CheckoutStrings strings;
  final TextEditingController controller;
  final int? areaIndex;
  final ValueChanged<String> onTableChanged;
  final ValueChanged<int?> onAreaSelected;

  @override
  Widget build(BuildContext context) {
    final areas = [strings.areaInside, strings.areaTerrace];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          onChanged: onTableChanged,
          decoration: InputDecoration(
            labelText: strings.tableFieldLabel,
            hintText: strings.tableFieldHint,
            border: const OutlineInputBorder(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs8),
          child: Text(strings.orSeparator,
              style:
                  AppTextStyles.labelMd.copyWith(color: AppColors.textMuted)),
        ),
        Wrap(
          spacing: AppSpacing.xs8,
          children: [
            for (var i = 0; i < areas.length; i++)
              ChoiceChip(
                label: Text(areas[i]),
                selected: areaIndex == i,
                onSelected: (_) => onAreaSelected(i),
              ),
          ],
        ),
      ],
    );
  }
}

class PickupDetails extends ConsumerWidget {
  const PickupDetails({super.key, required this.strings});

  final CheckoutStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timing = ref.watch(checkoutDraftProvider).pickupTiming;
    final slots = upcomingPickupSlots(DateTime.now().toUtc());

    return Wrap(
      spacing: AppSpacing.xs8,
      runSpacing: AppSpacing.xs8,
      children: [
        ChoiceChip(
          label: Text(strings.slotNow),
          selected: timing?.isNow ?? true,
          onSelected: (_) => ref
              .read(checkoutDraftProvider.notifier)
              .setPickupTiming(const PickupTiming.now()),
        ),
        for (final slot in slots)
          ChoiceChip(
            label: Text(slot.label),
            selected:
                !(timing?.isNow ?? true) && timing?.slotUtc == slot.startUtc,
            onSelected: (_) => ref
                .read(checkoutDraftProvider.notifier)
                .setPickupTiming(PickupTiming.slot(slot.startUtc)),
          ),
      ],
    );
  }
}

class DeliveryDetails extends ConsumerWidget {
  const DeliveryDetails({
    super.key,
    required this.strings,
    required this.textController,
    required this.newLabel,
    required this.onNewLabel,
    required this.showForm,
    required this.onToggleForm,
    required this.saving,
    required this.onSave,
  });

  final CheckoutStrings strings;
  final TextEditingController textController;
  final AddressLabel newLabel;
  final ValueChanged<AddressLabel> onNewLabel;
  final bool showForm;
  final VoidCallback onToggleForm;
  final bool saving;
  final VoidCallback onSave;

  String _labelName(AppLang lang, AddressLabel label) => switch (label) {
        AddressLabel.home => strings.labelHome,
        AddressLabel.work => strings.labelWork,
        AddressLabel.other => strings.labelOther,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final auth = ref.watch(authControllerProvider);
    final googleUserId = auth.googleUser?.id ?? '';
    final addressesAsync = ref.watch(addressesProvider(googleUserId));
    final draftAddressId = ref.watch(checkoutDraftProvider).addressId;
    final labels = {
      for (final label in AddressLabel.values) label: _labelName(lang, label),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        addressesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xs8),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => Text(
            strings.noAddressesLine,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
          ),
          data: (addresses) => addresses.isEmpty
              ? Text(
                  strings.noAddressesLine,
                  style:
                      AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(strings.savedAddressesLabel,
                        style: AppTextStyles.labelMd
                            .copyWith(color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs8),
                    for (final address in addresses)
                      AddressOption(
                        selected: draftAddressId == address.id,
                        title: '${labels[address.label]} · ${address.addressText}',
                        onTap: () => ref
                            .read(checkoutDraftProvider.notifier)
                            .setAddressId(address.id),
                      ),
                  ],
                ),
        ),
        if (!showForm)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onToggleForm,
              child: Text(strings.addAddressTitle),
            ),
          )
        else ...[
          const SizedBox(height: AppSpacing.xs8),
          Wrap(
            spacing: AppSpacing.xs8,
            children: [
              for (final entry in labels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: newLabel == entry.key,
                  onSelected: (_) => onNewLabel(entry.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs8),
          TextField(
            controller: textController,
            decoration: InputDecoration(
              labelText: strings.addressLineLabel,
              hintText: strings.addressLineHint,
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.xs8),
          FilledButton.tonal(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.addAddressCta),
          ),
        ],
      ],
    );
  }
}

class AddressOption extends StatelessWidget {
  const AddressOption({
    super.key,
    required this.selected,
    required this.title,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Flat selectable row (border only, no shadow): nested cards inside the
    // mode-details card would double the chrome.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs8),
      child: Material(
        color: selected ? AppColors.primaryFixedTint : AppColors.paperWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md8),
          side: BorderSide(
            color: selected
                ? AppColors.primary
                : AppColors.outline.withValues(alpha: 0.25),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.xs8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
