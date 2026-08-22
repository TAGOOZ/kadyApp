// Cart screen (issue #003): lines with qty steppers, per-line modifier
// summary, remove, order-notes field and a sticky totals footer. Continue
// requires AuthPhase.ready — guests get the save-progress prompt instead
// (RLS on `orders` forbids guest inserts; the auth slice takes over there).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_checkout.dart';
import '../../core/l10n/strings_menu.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/orders_repository.dart';
import '../../domain/auth_controller.dart';
import '../../domain/cart_controller.dart';
import '../menu/item_detail_sheet.dart' show MenuPhotoPlaceholder;
import '../auth/guest_save_prompt.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final strings = CheckoutStringsCatalog.of(lang);
    final lines = ref.watch(cartProvider);
    final subtotal = ref.watch(subtotalProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.cartTitle)),
      body: lines.isEmpty
          ? _EmptyCart(strings: strings)
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter16,
                      AppSpacing.xs8,
                      AppSpacing.gutter16,
                      AppSpacing.sm16,
                    ),
                    itemCount: lines.length + 1,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.xs8),
                    itemBuilder: (context, index) => index == lines.length
                        ? _OrderNotesField(strings: strings)
                        : _CartLineTile(line: lines[index]),
                  ),
                ),
                _StickyFooter(
                  subtotalEgp: subtotal,
                  strings: strings,
                  onContinue: () => _continueToPayment(context, ref),
                ),
              ],
            ),
    );
  }

  void _continueToPayment(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authControllerProvider);
    if (auth.phase == AuthPhase.ready && auth.googleUser != null) {
      context.push('/mode-selection');
      return;
    }
    // Guest (RLS blocks their orders) → registration prompt; the auth slice
    // owns what happens next. Nothing else happens here by design.
    showGuestSavePrompt(context);
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.strings});

  final CheckoutStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: AppColors.parchment,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child:
                Icon(Icons.shopping_cart_outlined, size: 42, color: AppColors.coffeeBean),
          ),
          const SizedBox(height: AppSpacing.sm16),
          Text(strings.emptyTitle, style: AppTextStyles.titleMd),
          const SizedBox(height: AppSpacing.xs8),
          Text(
            strings.emptyBody,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.md24),
          FilledButton(
            onPressed: () => context.go('/menu'),
            child: Text(strings.emptyCta),
          ),
        ],
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeNotifierProvider);
    final checkout = CheckoutStringsCatalog.of(lang);
    final menu = MenuStringsCatalog.of(lang);

    String? modifiersSummary;
    final parts = <String>[
      if (line.config.sizeIndex != 0) menu.sizeNames[line.config.sizeIndex],
      if (line.config.sugarIndex != 0) menu.sugarNames[line.config.sugarIndex],
      for (final addon in line.config.addons) menu.addonName(addon),
    ];
    if (parts.isNotEmpty) {
      modifiersSummary = parts.join(' · ');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MenuPhotoPlaceholder(height: 64, width: 64, iconSize: 28),
            const SizedBox(width: AppSpacing.xs8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.item.name(lang),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppTextStyles.titleMd.copyWith(fontSize: 15),
                        ),
                      ),
                      IconButton(
                        tooltip: checkout.removeTooltip,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref
                            .read(cartProvider.notifier)
                            .removeLine(line),
                        icon: const Icon(Icons.delete_outline, size: 20),
                      ),
                    ],
                  ),
                  if (modifiersSummary != null)
                    Text(
                      modifiersSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.outline),
                    ),
                  if (line.config.note != null &&
                      line.config.note!.trim().isNotEmpty)
                    Text(
                      '“${line.config.note}”',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StepperIcon(
                        icon: Icons.remove,
                        tooltip: checkout.decreaseTooltip,
                        onTap: () => ref
                            .read(cartProvider.notifier)
                            .setQty(line, line.qty - 1),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${line.qty}',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.titleMd.copyWith(fontSize: 16),
                        ),
                      ),
                      _StepperIcon(
                        icon: Icons.add,
                        tooltip: checkout.increaseTooltip,
                        onTap: () => ref
                            .read(cartProvider.notifier)
                            .setQty(line, line.qty + 1),
                      ),
                      const Spacer(),
                      Text(
                        checkout.egp(line.lineTotalEgp),
                        style: AppTextStyles.labelMd.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperIcon extends StatelessWidget {
  const _StepperIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.outline.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _OrderNotesField extends ConsumerStatefulWidget {
  const _OrderNotesField({required this.strings});

  final CheckoutStrings strings;

  @override
  ConsumerState<_OrderNotesField> createState() => _OrderNotesFieldState();
}

class _OrderNotesFieldState extends ConsumerState<_OrderNotesField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(checkoutDraftProvider).notes,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (value) =>
          ref.read(checkoutDraftProvider.notifier).setNotes(value),
      decoration: InputDecoration(
        labelText: widget.strings.notesLabel,
        hintText: widget.strings.notesHint,
        border: const OutlineInputBorder(),
      ),
      textInputAction: TextInputAction.done,
      maxLines: 2,
    );
  }
}

class _StickyFooter extends StatelessWidget {
  const _StickyFooter({
    required this.subtotalEgp,
    required this.strings,
    required this.onContinue,
  });

  final int subtotalEgp;
  final CheckoutStrings strings;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        boxShadow: AppShadows.coffeeShadows(
          offset: const Offset(0, -4),
          blurRadius: 12,
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.margin20,
        AppSpacing.sm16,
        AppSpacing.margin20,
        AppSpacing.md24,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(strings.subtotalRow, style: AppTextStyles.bodyLg),
                Text(
                  strings.egp(subtotalEgp),
                  style: AppTextStyles.titleMd.copyWith(fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm16),
            FilledButton(
              onPressed: onContinue,
              child: Text(strings.continueCta),
            ),
          ],
        ),
      ),
    );
  }
}
