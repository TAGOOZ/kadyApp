// Profile & settings tab (#011): editable fields, delivery addresses CRUD,
// notification prefs, language switch, vouchers and logout. Guest sessions
// get a compact sign-in panel instead of the account sections.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_auth.dart';
import '../../core/l10n/strings_profile.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repos/address.dart';
import '../../data/repos/customers_repository.dart';
import '../../domain/auth_controller.dart';
import '../../domain/loyalty_controller.dart';
import '../../domain/session_controller.dart';
import 'widgets/addresses_section.dart';
import 'widgets/contact_social_section.dart';
import 'widgets/edit_field_sheet.dart';
import 'widgets/language_row.dart';
import 'widgets/notifications_card.dart';
import 'widgets/profile_header.dart';
import 'widgets/vouchers_section.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  CustomerRecord? _profile;
  List<AddressRecord> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final auth = ref.read(authControllerProvider);
    final uid = auth.googleUser?.id;
    if (auth.phase != AuthPhase.ready || uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final repo = ref.read(customerProfileRepoProvider);
      final profile = await repo.loadByGoogleUserId(uid);
      final addresses = await repo.listAddresses(googleUserId: uid);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _addresses = addresses;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  ProfileStrings get _strings =>
      ProfileStringsCatalog.of(ref.read(localeNotifierProvider));

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toastWithUndo(String message, String actionLabel, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: actionLabel, onPressed: undo),
        ),
      );
  }

  // -- profile fields --------------------------------------------------------

  Future<void> _editTextField({
    required String title,
    required String initialValue,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String raw)? validate,
    int maxLines = 1,
    Key? fieldKey,
    required CustomerPatch Function(String text) patchFor,
  }) async {
    final s = _strings;
    CustomerRecord? saved;
    await showEditFieldSheet(
      context,
      title: title,
      initialValue: initialValue,
      saveLabel: s.saveLabel,
      cancelLabel: s.cancelLabel,
      saveFailedError: s.saveFailedError,
      hint: hint,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validate: validate,
      maxLines: maxLines,
      textFieldKey: fieldKey,
      onSave: (value) async {
        final phone = _profile?.phone;
        if (phone == null) throw StateError('profile not loaded');
        saved = await ref
            .read(customerProfileRepoProvider)
            .updateProfile(phone: phone, patch: patchFor(value.text));
      },
    );
    if (saved != null && mounted) {
      setState(() => _profile = saved);
      _toast(s.savedSnackbar);
    }
  }

  Future<void> _editName(ProfileStrings s) => _editTextField(
        title: s.editField(s.fieldName),
        initialValue: _profile?.name ?? '',
        fieldKey: const Key('edit_name_field'),
        validate: (raw) => raw.trim().isEmpty ? s.nameRequiredError : null,
        patchFor: (text) => CustomerPatch(name: text),
      );

  Future<void> _editEmail(ProfileStrings s) => _editTextField(
        title: s.editField(s.fieldEmail),
        initialValue: _profile?.email ?? '',
        fieldKey: const Key('edit_email_field'),
        keyboardType: TextInputType.emailAddress,
        hint: s.optionalHint,
        validate: (raw) {
          final value = raw.trim();
          if (value.isEmpty) return null;
          return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)
              ? null
              : s.emailInvalidError;
        },
        patchFor: (text) => CustomerPatch(email: text),
      );

  Future<void> _editBirthdate(ProfileStrings s) => _editTextField(
        title: s.editField(s.fieldBirthdate),
        initialValue: _birthdateText,
        fieldKey: const Key('edit_birthdate_field'),
        keyboardType: TextInputType.datetime,
        hint: 'YYYY-MM-DD',
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
          LengthLimitingTextInputFormatter(10),
        ],
        validate: (raw) => parseBirthdateInput(raw) == null
            ? s.birthdateInvalidError
            : null,
        patchFor: (text) => CustomerPatch(birthdate: parseBirthdateInput(text)),
      );

  Future<void> _editCity(ProfileStrings s) => _editTextField(
        title: s.editField(s.fieldCity),
        initialValue: _profile?.city ?? '',
        fieldKey: const Key('edit_city_field'),
        hint: s.optionalHint,
        patchFor: (text) => CustomerPatch(city: text),
      );

  String get _birthdateText {
    final date = _profile?.birthdate;
    return date == null ? '' : date.toIso8601String().substring(0, 10);
  }

  Future<void> _toggleStudent(bool value) async {
    final s = _strings;
    try {
      final updated =
          await _patch(CustomerPatch(isStudent: value));
      if (!mounted) return;
      setState(() => _profile = updated);
      _toast(s.savedSnackbar);
    } catch (_) {
      if (mounted) _toast(s.saveFailedError);
    }
  }

  Future<CustomerRecord> _patch(CustomerPatch patch) async {
    final phone = _profile?.phone;
    if (phone == null) throw StateError('profile not loaded');
    return ref
        .read(customerProfileRepoProvider)
        .updateProfile(phone: phone, patch: patch);
  }

  // -- addresses -------------------------------------------------------------

  Future<void> _openAddressSheet({AddressRecord? existing}) async {
    final s = _strings;
    AddressRecord? saved;
    await showEditFieldSheet(
      context,
      title: existing == null ? s.newAddressTitle : s.editAddressTitle,
      initialValue: existing?.addressText ?? '',
      saveLabel: s.saveLabel,
      cancelLabel: s.cancelLabel,
      saveFailedError: s.saveFailedError,
      maxLines: 2,
      labelChoices: [
        s.addressLabelHome,
        s.addressLabelWork,
        s.addressLabelOther,
      ],
      initialLabelIndex: existing?.label.index ?? 0,
      textFieldKey: const Key('address_text_field'),
      validate: (raw) =>
          raw.trim().isEmpty ? s.addressRequiredError : null,
      onSave: (value) async {
        var index = value.labelIndex;
        if (index < 0) index = 0;
        if (index > 2) index = 2;
        final label = AddressLabel.values[index];
        final uid = ref.read(authControllerProvider).googleUser!.id;
        final repo = ref.read(customerProfileRepoProvider);
        saved = existing == null
            ? await repo.addAddress(
                googleUserId: uid,
                label: label,
                addressText: value.text,
              )
            : await repo.updateAddress(
                address: AddressRecord(
                  id: existing.id,
                  phone: existing.phone,
                  label: label,
                  addressText: value.text,
                ),
              );
      },
    );
    if (saved != null && mounted) {
      setState(() {
        _addresses.removeWhere((a) => a.id == saved!.id);
        _addresses.add(saved!);
      });
    }
  }

  void _onAddressDismissed(AddressRecord address) {
    // Optimistic removal keeps the Dismissible out of the tree this frame.
    setState(() => _addresses.removeWhere((a) => a.id == address.id));
    _deleteAddressOnServer(address);
  }

  Future<void> _deleteAddressOnServer(AddressRecord address) async {
    final s = _strings;
    try {
      await ref
          .read(customerProfileRepoProvider)
          .deleteAddress(addressId: address.id);
      if (!mounted) return;
      _toastWithUndo(
        s.addressDeletedSnackbar,
        s.undoLabel,
        () => _restoreAddress(address),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addresses.add(address);
      });
      _toast(s.saveFailedError);
    }
  }

  Future<void> _restoreAddress(AddressRecord address) async {
    final s = _strings;
    try {
      final restored = await ref
          .read(customerProfileRepoProvider)
          .addAddress(
            googleUserId:
                ref.read(authControllerProvider).googleUser?.id ?? '',
            label: address.label,
            addressText: address.addressText,
          );
      if (!mounted) return;
      setState(() => _addresses.add(restored));
    } catch (_) {
      if (mounted) _toast(s.saveFailedError);
    }
  }

  // -- loyalty / logout ------------------------------------------------------

  Future<void> _refreshLoyalty() async {
    final uid = ref.read(authControllerProvider).googleUser?.id;
    if (uid == null) return;
    try {
      await ref.read(loyaltyProvider.notifier).refreshFor(uid);
    } catch (_) {}
  }

  Future<void> _confirmLogout(ProfileStrings s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.logoutConfirmTitle),
        content: Text(s.logoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              s.logoutTile,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    ref.read(loyaltyProvider.notifier).reset();
    await ref.read(authControllerProvider.notifier).signOut();
    await ref.read(sessionControllerProvider.notifier).resetToWelcome();
  }

  // -- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final s = ProfileStringsCatalog.of(lang);
    final auth = ref.watch(authControllerProvider);
    final loyalty = ref.watch(loyaltyProvider);
    final ready = auth.phase == AuthPhase.ready && auth.googleUser != null;

    final googleName = auth.googleUser?.name ?? '';
    final displayName = ready
        ? (_profile?.name.isNotEmpty ?? false)
            ? _profile!.name
            : (googleName.isNotEmpty ? googleName : s.guestName)
        : s.guestName;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.margin20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xs8),
              ProfileHeader(
                name: displayName,
                tier: loyalty.tier,
                strings: s,
                isGuest: !ready,
                onCameraTap: () => _toast(s.comingSoon),
              ),
              const SizedBox(height: AppSpacing.sm16),
              _SummaryStrip(
                text: s.summaryStrip(loyalty.points, loyalty.stamps),
                onTap: _refreshLoyalty,
              ),
              const SizedBox(height: AppSpacing.sm16),
              if (_loading && ready)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!ready) ...[
                _GuestPanel(strings: s, onSignIn: _guestSignIn),
              ] else ...[
                _Section(
                  title: s.myDataSection,
                  child: Column(
                    children: [
                      _FieldRow(
                        rowKey: const Key('profile_row_name'),
                        label: s.fieldName,
                        value: _profile?.name ?? '',
                        onTap: () => _editName(s),
                      ),
                      _FieldRow(
                        rowKey: const Key('profile_row_phone'),
                        label: s.fieldPhone,
                        value: _profile?.phone ??
                            auth.phone ??
                            s.notSetValue,
                        trailing: const Icon(Icons.lock_outline,
                            size: 18, color: AppColors.outline),
                      ),
                      _FieldRow(
                        rowKey: const Key('profile_row_email'),
                        label: s.fieldEmail,
                        value: _emailValue(s),
                        muted: (_profile?.email ?? '').isEmpty,
                        onTap: () => _editEmail(s),
                      ),
                      _FieldRow(
                        rowKey: const Key('profile_row_birthdate'),
                        label: s.fieldBirthdate,
                        value: _birthdateText.isEmpty
                            ? s.notSetValue
                            : _birthdateText,
                        muted: _birthdateText.isEmpty,
                        onTap: () => _editBirthdate(s),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(s.fieldStudent,
                                style: AppTextStyles.bodyLg),
                          ),
                          Switch(
                            key: const Key('profile_row_student_switch'),
                            value: _profile?.isStudent ?? false,
                            onChanged: _toggleStudent,
                          ),
                        ],
                      ),
                      _FieldRow(
                        rowKey: const Key('profile_row_city'),
                        label: s.fieldCity,
                        value: (_profile?.city ?? '').isEmpty
                            ? s.notSetValue
                            : _profile!.city!,
                        muted: (_profile?.city ?? '').isEmpty,
                        onTap: () => _editCity(s),
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: s.addressesSection,
                  child: AddressesSection(
                    addresses: _addresses,
                    strings: s,
                    onAdd: () => _openAddressSheet(),
                    onEdit: (address) =>
                        _openAddressSheet(existing: address),
                    onDelete: _onAddressDismissed,
                  ),
                ),
                _Section(
                  title: s.notificationsSection,
                  child: NotificationsCard(strings: s),
                ),
                const _Section(child: LanguageRow()),
                _Section(
                  title: s.vouchersSection,
                  child: VouchersSection(
                    vouchers: loyalty.vouchers,
                    strings: s,
                  ),
                ),
                _LogoutTile(label: s.logoutTile, onTap: () => _confirmLogout(s)),
              ],
              ContactSocialSection(lang: lang),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + AppSpacing.lg32),
            ],
          ),
        ),
      ),
    );
  }

  String _emailValue(ProfileStrings s) {
    final email = _profile?.email ?? '';
    return email.isEmpty ? s.notSetValue : email;
  }

  Future<void> _guestSignIn() async {
    final ok = await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!ok && mounted) {
      _toast(AuthStringsCatalog.of(ref.read(localeNotifierProvider))
          .googleUnavailable);
    }
  }
}

// -- shared card chrome ------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(title!, style: AppTextStyles.titleSm),
          const SizedBox(height: AppSpacing.sm16 - 4),
        ],
        child,
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm16),
      padding: const EdgeInsets.all(AppSpacing.sm16),
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        boxShadow: AppShadows.coffeeShadows(
          offset: const Offset(0, 4),
          blurRadius: 14,
        ),
      ),
      child: content,
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('profile_summary_strip'),
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm16,
          vertical: AppSpacing.sm16 - 4,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [
            AppColors.primaryContainer,
            AppColors.primary,
          ]),
          borderRadius:
              const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
          boxShadow: AppShadows.coffeeShadows(
            offset: const Offset(0, 4),
            blurRadius: 14,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.stars_rounded, size: 22, color: Colors.white),
            const SizedBox(width: AppSpacing.xs8),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.priceSm.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.rowKey,
    required this.label,
    required this.value,
    this.muted = false,
    this.trailing,
    this.onTap,
  });

  final Key rowKey;
  final String label;
  final String value;
  final bool muted;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final editable = onTap != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs8 + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelMd.copyWith(
                     color: AppColors.textMuted,
                   ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLg.copyWith(
                    fontWeight: FontWeight.w600,
                    color: muted ? AppColors.textMuted : AppColors.coffeeBean,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs8),
              child: trailing!,
            )
          else if (editable)
            const Padding(
              padding: EdgeInsetsDirectional.only(start: AppSpacing.xs8),
              child: Icon(Icons.edit_outlined, size: 18),
            ),
        ],
      ),
    );

    if (!editable) return KeyedSubtree(key: rowKey, child: row);
    return InkWell(
      key: rowKey,
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.md8)),
      child: row,
    );
  }
}

class _GuestPanel extends StatelessWidget {
  const _GuestPanel({required this.strings, required this.onSignIn});

  final ProfileStrings strings;
  final Future<void> Function() onSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('profile_guest_panel'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm16),
      padding: const EdgeInsets.all(AppSpacing.md24),
      decoration: BoxDecoration(
        color: AppColors.paperWhite,
        borderRadius:
            const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
        border: Border.all(color: AppColors.primaryFixedTint),
      ),
      child: Column(
        children: [
          const Icon(Icons.savings_outlined, size: 36, color: AppColors.secondary),
          const SizedBox(height: AppSpacing.sm16),
          Text(
            strings.guestPanelTitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMd,
          ),
          const SizedBox(height: AppSpacing.xs8),
          Text(
            strings.guestPanelBody,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm
                 .copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md24),
          FilledButton.icon(
            key: const Key('profile_guest_google_button'),
            onPressed: onSignIn,
            icon: const Icon(Icons.login, size: 18),
            label: Text(strings.guestSignInCta),
          ),
        ],
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('profile_logout'),
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.07),
          borderRadius:
              const BorderRadius.all(Radius.circular(AppRadii.mdLg12)),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, size: 20, color: AppColors.error),
            const SizedBox(width: AppSpacing.xs8),
            Text(
              label,
              style: AppTextStyles.bodyLg.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
