// Profile & settings copy (#011), keyed by AppLang (mirrors AppStrings pattern).
import 'app_strings.dart';
import '../../data/repos/address.dart';
import '../../domain/loyalty_controller.dart';

class ProfileStrings {
  const ProfileStrings({
    required this.screenTitle,
    required this.comingSoon,
    required this.guestName,
    required this.tierBronze,
    required this.tierSilver,
    required this.tierGold,
    required this.summaryStripTemplate,
    required this.myDataSection,
    required this.fieldName,
    required this.fieldPhone,
    required this.fieldPhoneLockedHint,
    required this.fieldEmail,
    required this.fieldBirthdate,
    required this.fieldStudent,
    required this.fieldCity,
    required this.optionalHint,
    required this.notSetValue,
    required this.editTitle,
    required this.saveLabel,
    required this.cancelLabel,
    required this.savedSnackbar,
    required this.saveFailedError,
    required this.nameRequiredError,
    required this.birthdateInvalidError,
    required this.emailInvalidError,
    required this.addressesSection,
    required this.addressLabelHome,
    required this.addressLabelWork,
    required this.addressLabelOther,
    required this.addAddressLabel,
    required this.newAddressTitle,
    required this.editAddressTitle,
    required this.addressRequiredError,
    required this.addressDeletedSnackbar,
    required this.undoLabel,
    required this.notificationsSection,
    required this.notifOrders,
    required this.notifOffers,
    required this.notifMatchNights,
    required this.notifExams,
    required this.vouchersSection,
    required this.voucherFreeDrink,
    required this.voucherFreeTopping,
    required this.voucherFreeSnack,
    required this.voucherValidChip,
    required this.voucherExpiredChip,
    required this.voucherExpiryLabelTemplate,
    required this.vouchersEmpty,
    required this.logoutTile,
    required this.logoutConfirmTitle,
    required this.logoutConfirmBody,
    required this.guestPanelTitle,
    required this.guestPanelBody,
    required this.guestSignInCta,
    required this.contactSectionTitle,
    required this.contactSectionSubtitle,
    required this.socialFacebook,
    required this.socialInstagram,
    required this.socialTiktok,
    required this.contactPhoneLabel,
    required this.contactPhoneNumber,
    required this.contactWhatsAppLabel,
    required this.contactWhatsAppNumber,
  });

  final String screenTitle;
  final String comingSoon;
  final String guestName;
  final String tierBronze;
  final String tierSilver;
  final String tierGold;
  final String summaryStripTemplate;
  final String myDataSection;
  final String fieldName;
  final String fieldPhone;
  final String fieldPhoneLockedHint;
  final String fieldEmail;
  final String fieldBirthdate;
  final String fieldStudent;
  final String fieldCity;
  final String optionalHint;
  final String notSetValue;
  final String editTitle;
  final String saveLabel;
  final String cancelLabel;
  final String savedSnackbar;
  final String saveFailedError;
  final String nameRequiredError;
  final String birthdateInvalidError;
  final String emailInvalidError;
  final String addressesSection;
  final String addressLabelHome;
  final String addressLabelWork;
  final String addressLabelOther;
  final String addAddressLabel;
  final String newAddressTitle;
  final String editAddressTitle;
  final String addressRequiredError;
  final String addressDeletedSnackbar;
  final String undoLabel;
  final String notificationsSection;
  final String notifOrders;
  final String notifOffers;
  final String notifMatchNights;
  final String notifExams;
  final String vouchersSection;
  final String voucherFreeDrink;
  final String voucherFreeTopping;
  final String voucherFreeSnack;
  final String voucherValidChip;
  final String voucherExpiredChip;
  final String voucherExpiryLabelTemplate;
  final String vouchersEmpty;
  final String logoutTile;
  final String logoutConfirmTitle;
  final String logoutConfirmBody;
  final String guestPanelTitle;
  final String guestPanelBody;
  final String guestSignInCta;
  final String contactSectionTitle;
  final String contactSectionSubtitle;
  final String socialFacebook;
  final String socialInstagram;
  final String socialTiktok;
  final String contactPhoneLabel;
  final String contactPhoneNumber;
  final String contactWhatsAppLabel;
  final String contactWhatsAppNumber;

  String editField(String field) => editTitle.replaceAll('{field}', field);

  String tierLabel(Tier tier) => switch (tier) {
        Tier.bronze => tierBronze,
        Tier.silver => tierSilver,
        Tier.gold => tierGold,
      };

  /// §11.11 numerals: Western `0123` in both languages.
  String summaryStrip(int points, int stamps) => summaryStripTemplate
      .replaceAll('{points}', '$points')
      .replaceAll('{stamps}', '$stamps');

  String addressLabel(AddressLabel label) => switch (label) {
        AddressLabel.home => addressLabelHome,
        AddressLabel.work => addressLabelWork,
        AddressLabel.other => addressLabelOther,
      };

  String voucherLabel(VoucherType type) => switch (type) {
        VoucherType.freeDrink => voucherFreeDrink,
        VoucherType.freeTopping => voucherFreeTopping,
        VoucherType.freeSnack => voucherFreeSnack,
      };

  String voucherExpiryLabel(DateTime expiresAt) {
    final d = '${expiresAt.day}/${expiresAt.month}/${expiresAt.year}';
    return voucherExpiryLabelTemplate.replaceAll('{date}', d);
  }
}

abstract final class ProfileStringsCatalog {
  static const Map<AppLang, ProfileStrings> values = {
    AppLang.ar: ProfileStrings(
      screenTitle: 'الملف الشخصي',
      comingSoon: 'قريبًا',
      guestName: 'زائر',
      tierBronze: 'برونزي',
      tierSilver: 'فضي',
      tierGold: 'ذهبي',
      summaryStripTemplate: '{points} نقطة · بطاقة {stamps}/10',
      myDataSection: 'بياناتي',
      fieldName: 'الاسم',
      fieldPhone: 'رقم الموبايل',
      fieldPhoneLockedHint: 'هويّتك في التطبيق — لا يمكن تغييره',
      fieldEmail: 'البريد الإلكتروني',
      fieldBirthdate: 'تاريخ الميلاد',
      fieldStudent: 'طالب؟',
      fieldCity: 'المدينة',
      optionalHint: 'اختياري',
      notSetValue: 'مش متحدد',
      editTitle: 'تعديل {field}',
      saveLabel: 'حفظ',
      cancelLabel: 'إلغاء',
      savedSnackbar: 'تم الحفظ ✓',
      saveFailedError: 'حصل خطأ أثناء الحفظ، حاول تاني',
      nameRequiredError: 'اكتب اسمك',
      birthdateInvalidError: 'اكتب التاريخ بصيغة YYYY-MM-DD',
      emailInvalidError: 'اكتب بريدًا إلكترونيًا صحيحًا',
      addressesSection: 'عناوين التوصيل',
      addressLabelHome: 'بيت',
      addressLabelWork: 'شغل',
      addressLabelOther: 'أخرى',
      addAddressLabel: 'إضافة عنوان',
      newAddressTitle: 'عنوان جديد',
      editAddressTitle: 'تعديل العنوان',
      addressRequiredError: 'اكتب العنوان',
      addressDeletedSnackbar: 'اتمسح العنوان',
      undoLabel: 'تراجع',
      notificationsSection: 'الإشعارات',
      notifOrders: 'تحديثات الطلبات',
      notifOffers: 'العروض',
      notifMatchNights: 'ليالي الماتشات',
      notifExams: 'موسم الامتحانات',
      vouchersSection: 'مكافآتي',
      voucherFreeDrink: 'مشروب مجاني',
      voucherFreeTopping: 'توبينج مجاني',
      voucherFreeSnack: 'سناكس مجاني',
      voucherValidChip: 'صالحة',
      voucherExpiredChip: 'منتهية',
      voucherExpiryLabelTemplate: 'صالح حتى {date}',
      vouchersEmpty: 'مفيش مكافآت لسه — العب واكسب!',
      logoutTile: 'تسجيل الخروج',
      logoutConfirmTitle: 'تسجيل الخروج؟',
      logoutConfirmBody: 'نقاطك وطوابعك محفوظة على رقم موبايلك، وتقدر ترجع في أي وقت.',
      guestPanelTitle: 'خلي نقاطك معاك!',
      guestPanelBody:
          'سجّل بحساب Google عشان نقاطك وطوابعك ومكافآتك وعناوينك تفضل محفوظة معاك.',
      guestSignInCta: 'سجّل بحساب Google',
      contactSectionTitle: 'تواصل معنا',
      contactSectionSubtitle: 'تابعنا على',
      socialFacebook: 'فيسبوك',
      socialInstagram: 'إنستجرام',
      socialTiktok: 'تيك توك',
      contactPhoneLabel: 'هاتف',
      contactPhoneNumber: '045 2508799',
      contactWhatsAppLabel: 'واتساب',
      contactWhatsAppNumber: '+20 120 626 8500',
    ),
    AppLang.en: ProfileStrings(
      screenTitle: 'Profile',
      comingSoon: 'Coming soon',
      guestName: 'Guest',
      tierBronze: 'Bronze',
      tierSilver: 'Silver',
      tierGold: 'Gold',
      summaryStripTemplate: '{points} pts · card {stamps}/10',
      myDataSection: 'My details',
      fieldName: 'Name',
      fieldPhone: 'Mobile number',
      fieldPhoneLockedHint: 'Your identity in the app — can\'t be changed',
      fieldEmail: 'Email',
      fieldBirthdate: 'Birthdate',
      fieldStudent: 'Student?',
      fieldCity: 'City',
      optionalHint: 'optional',
      notSetValue: 'Not set',
      editTitle: 'Edit {field}',
      saveLabel: 'Save',
      cancelLabel: 'Cancel',
      savedSnackbar: 'Saved ✓',
      saveFailedError: 'Something went wrong saving, please try again',
      nameRequiredError: 'Please enter your name',
      birthdateInvalidError: 'Use the YYYY-MM-DD format',
      emailInvalidError: 'Enter a valid email address',
      addressesSection: 'Delivery addresses',
      addressLabelHome: 'Home',
      addressLabelWork: 'Work',
      addressLabelOther: 'Other',
      addAddressLabel: 'Add address',
      newAddressTitle: 'New address',
      editAddressTitle: 'Edit address',
      addressRequiredError: 'Please enter the address',
      addressDeletedSnackbar: 'Address deleted',
      undoLabel: 'Undo',
      notificationsSection: 'Notifications',
      notifOrders: 'Order updates',
      notifOffers: 'Offers',
      notifMatchNights: 'Match nights',
      notifExams: 'Exam season',
      vouchersSection: 'My rewards',
      voucherFreeDrink: 'Free drink',
      voucherFreeTopping: 'Free topping',
      voucherFreeSnack: 'Free snack',
      voucherValidChip: 'Valid',
      voucherExpiredChip: 'Expired',
      voucherExpiryLabelTemplate: 'Valid until {date}',
      vouchersEmpty: 'No rewards yet — play and earn!',
      logoutTile: 'Sign out',
      logoutConfirmTitle: 'Sign out?',
      logoutConfirmBody:
          'Your points and stamps stay on your phone number; sign back in anytime.',
      guestPanelTitle: 'Keep your points!',
      guestPanelBody:
          'Sign in with Google to keep your points, stamps, rewards and '
          'addresses on any device.',
      guestSignInCta: 'Sign in with Google',
      contactSectionTitle: 'Contact us',
      contactSectionSubtitle: 'Follow us on',
      socialFacebook: 'Facebook',
      socialInstagram: 'Instagram',
      socialTiktok: 'TikTok',
      contactPhoneLabel: 'Phone',
      contactPhoneNumber: '045 2508799',
      contactWhatsAppLabel: 'WhatsApp',
      contactWhatsAppNumber: '+20 120 626 8500',
    ),
  };

  static ProfileStrings of(AppLang lang) => values[lang]!;
}
