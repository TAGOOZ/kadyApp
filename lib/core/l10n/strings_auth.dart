// Auth funnel + guest-save copy, keyed by AppLang (mirrors AppStrings pattern).
import 'app_strings.dart';

class AuthStrings {
  const AuthStrings({
    required this.welcomeGoogleCta,
    required this.welcomeSkip,
    required this.googleUnavailable,
    required this.phoneTitle,
    required this.phoneSubtitle,
    required this.phoneLabel,
    required this.phoneHint,
    required this.nameLabel,
    required this.nameRequiredError,
    required this.emailLabel,
    required this.studentLabel,
    required this.birthdateLabel,
    required this.cityLabel,
    required this.optionalHint,
    required this.saveAndContinue,
    required this.invalidPhoneError,
    required this.duplicatePhoneError,
    required this.saveFailedError,
    required this.guestSaveTitle,
    required this.guestSaveBodyTemplate,
    required this.guestSavePrimary,
    required this.guestSaveSecondary,
    required this.guestChipPoints,
    required this.guestChipStamp,
  });

  final String welcomeGoogleCta;
  final String welcomeSkip;
  final String googleUnavailable;
  final String phoneTitle;
  final String phoneSubtitle;
  final String phoneLabel;
  final String phoneHint;
  final String nameLabel;
  final String nameRequiredError;
  final String emailLabel;
  final String studentLabel;
  final String birthdateLabel;
  final String cityLabel;
  final String optionalHint;
  final String saveAndContinue;
  final String invalidPhoneError;
  final String duplicatePhoneError;
  final String saveFailedError;
  final String guestSaveTitle;
  final String guestSaveBodyTemplate;
  final String guestSavePrimary;
  final String guestSaveSecondary;
  final String guestChipPoints;
  final String guestChipStamp;

  String guestSaveBody(int points) =>
      guestSaveBodyTemplate.replaceAll('{points}', '$points');
}

abstract final class AuthStringsCatalog {
  static const Map<AppLang, AuthStrings> values = {
    AppLang.ar: AuthStrings(
      welcomeGoogleCta: 'المتابعة بحساب Google',
      welcomeSkip: 'تخطي الآن',
      googleUnavailable: 'تسجيل الدخول بجوجل غير مفعّل بعد',
      phoneTitle: 'إكمال التسجيل',
      phoneSubtitle: 'اربط نقاطك برقم موبايلك عشان تقدر تستخدمها في الفرع',
      phoneLabel: 'رقم الموبايل',
      phoneHint: '1001234567',
      nameLabel: 'الاسم',
      nameRequiredError: 'اكتب اسمك',
      emailLabel: 'البريد الإلكتروني',
      studentLabel: 'طالب؟',
      birthdateLabel: 'تاريخ الميلاد',
      cityLabel: 'المدينة',
      optionalHint: 'اختياري',
      saveAndContinue: 'حفظ ومتابعة',
      invalidPhoneError: 'أدخل رقمًا صحيحًا مثل +201001234567',
      duplicatePhoneError: 'الرقم مستخدم مع حساب آخر',
      saveFailedError: 'حصل خطأ أثناء الحفظ، حاول تاني',
      guestSaveTitle: 'خلي نقاطك معاك!',
      guestSaveBodyTemplate:
          'سجّل بحساب Google عشان نحفظ لك {points} نقطة وختم زيارتك الأولى',
      guestSavePrimary: 'سجّل بحساب Google',
      guestSaveSecondary: 'كمّل كزائر',
      guestChipPoints: 'نقاط المكافآت',
      guestChipStamp: 'ختم أول زيارة',
    ),
    AppLang.en: AuthStrings(
      welcomeGoogleCta: 'Continue with Google',
      welcomeSkip: 'Skip for now',
      googleUnavailable: 'Google sign-in isn\'t enabled yet',
      phoneTitle: 'Finish signing up',
      phoneSubtitle: 'Link your loyalty points to your phone number',
      phoneLabel: 'Mobile number',
      phoneHint: '1001234567',
      nameLabel: 'Name',
      nameRequiredError: 'Please enter your name',
      emailLabel: 'Email',
      studentLabel: 'Student?',
      birthdateLabel: 'Birthdate',
      cityLabel: 'City',
      optionalHint: 'optional',
      saveAndContinue: 'Save & continue',
      invalidPhoneError: 'Enter a valid number like +201001234567',
      duplicatePhoneError: 'This number is used with another account',
      saveFailedError: 'Something went wrong saving, please try again',
      guestSaveTitle: 'Keep your points!',
      guestSaveBodyTemplate:
          'Sign in with Google to save your {points} points and stamp your '
          'first visit',
      guestSavePrimary: 'Sign in with Google',
      guestSaveSecondary: 'Continue as guest',
      guestChipPoints: 'Reward points',
      guestChipStamp: 'First-visit stamp',
    ),
  };

  static AuthStrings of(AppLang lang) => values[lang]!;
}
