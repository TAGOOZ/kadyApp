// Post-Google phone collection — phone is the canonical Customer key.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/strings_auth.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/auth_controller.dart';

class PhoneCollectionScreen extends ConsumerStatefulWidget {
  const PhoneCollectionScreen({super.key});

  @override
  ConsumerState<PhoneCollectionScreen> createState() =>
      _PhoneCollectionScreenState();
}

class _PhoneCollectionScreenState extends ConsumerState<PhoneCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _birthdate;
  String? _email;
  DateTime? _birthdateValue;
  bool _isStudent = false;

  @override
  void initState() {
    super.initState();
    final google = ref.read(authControllerProvider).googleUser;
    _phone = TextEditingController();
    _name = TextEditingController(text: google?.name ?? '');
    _city = TextEditingController();
    _birthdate = TextEditingController();
    _email = (google?.email.isNotEmpty ?? false) ? google!.email : null;
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _city.dispose();
    _birthdate.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _birthdateValue = picked;
        _birthdate.text = picked.toIso8601String().substring(0, 10);
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authControllerProvider.notifier).submitPhone(
          rawPhone: _phone.text,
          name: _name.text,
          email: _email ?? '',
          isStudent: _isStudent,
          birthdate: _birthdateValue,
          city: _city.text,
        );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final authStrings = AuthStringsCatalog.of(lang);
    final auth = ref.watch(authControllerProvider);

    final inlineError = switch (auth.error) {
      AuthErrorCode.duplicatePhone => authStrings.duplicatePhoneError,
      AuthErrorCode.saveFailed => authStrings.saveFailedError,
      AuthErrorCode.googleUnavailable => authStrings.googleUnavailable,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(authStrings.phoneTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.margin20),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xs8),
                Text(authStrings.phoneSubtitle, style: AppTextStyles.bodySm),
                const SizedBox(height: AppSpacing.md24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs8),
                      child: Chip(
                        label: const Text('+20'),
                        labelStyle: AppTextStyles.bodyLg.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs8),
                    Expanded(
                      child: TextFormField(
                        key: const Key('auth_phone_field'),
                        controller: _phone,
                        keyboardType: TextInputType.number,
                        maxLength: 11,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: authStrings.phoneLabel,
                          hintText: authStrings.phoneHint,
                          counterText: '',
                          errorMaxLines: 2,
                        ),
                        style: AppTextStyles.bodyLg,
                        validator: (value) {
                          final phone = normalizeEgyptianPhone(value ?? '');
                          if (!isValidEgyptianPhone(phone)) {
                            return authStrings.invalidPhoneError;
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm16),
                TextFormField(
                  controller: _name,
                  decoration:
                      InputDecoration(labelText: authStrings.nameLabel),
                  style: AppTextStyles.bodyLg,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? authStrings.nameRequiredError
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm16),
                TextFormField(
                  initialValue: _email,
                  enabled: false,
                  decoration:
                      InputDecoration(labelText: authStrings.emailLabel),
                  style: AppTextStyles.bodyLg.copyWith(
                    color: AppColors.outline,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isStudent,
                  onChanged: (value) => setState(() => _isStudent = value),
                  title: Text(
                    authStrings.studentLabel,
                    style: AppTextStyles.bodyLg,
                  ),
                ),
                TextFormField(
                  readOnly: true,
                  onTap: _pickBirthdate,
                  controller: _birthdate,
                  decoration: InputDecoration(
                    labelText: authStrings.birthdateLabel,
                    helperText: authStrings.optionalHint,
                    suffixIcon: const Icon(Icons.calendar_month_outlined),
                  ),
                  style: AppTextStyles.bodyLg,
                ),
                const SizedBox(height: AppSpacing.sm16),
                TextFormField(
                  key: const Key('auth_city_field'),
                  controller: _city,
                  decoration: InputDecoration(
                    labelText: authStrings.cityLabel,
                    helperText: authStrings.optionalHint,
                  ),
                  style: AppTextStyles.bodyLg,
                ),
                if (inlineError != null) ...[
                  const SizedBox(height: AppSpacing.sm16),
                  Text(
                    inlineError,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg32),
                FilledButton(
                  key: const Key('auth_save_button'),
                  onPressed: auth.busy ? null : _submit,
                  child: auth.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(authStrings.saveAndContinue),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + AppSpacing.md24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
