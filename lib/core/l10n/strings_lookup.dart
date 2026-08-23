// Customer lookup strings catalog (#013) — mirrors the StaffStrings pattern
// (`app_strings.dart` is intentionally NOT edited; this file owns all
// user-facing copy for حساب العميل: search, profile card, manual reward
// sheet, visit dialog and activity log). ar default, en toggle.
// Numerals: Western 0123 in both languages (§11.11).
import 'app_strings.dart';

class LookupStrings {
  const LookupStrings({
    required this.screenTitle,
    required this.searchHint,
    required this.recentTitle,
    required this.noResults,
    required this.emptyTermHint,
    required this.statsPoints,
    required this.statsStamps,
    required this.statsStampsOfTemplate,
    required this.statsVisits,
    required this.tierBronze,
    required this.tierSilver,
    required this.tierGold,
    required this.recentOrdersTitle,
    required this.recentOrdersEmpty,
    required this.totalTemplate,
    required this.addRewardCta,
    required this.registerVisitCta,
    required this.rewardSheetTitle,
    required this.rewardPoints25,
    required this.rewardFreeDrink,
    required this.rewardFreeTopping,
    required this.reasonLabel,
    required this.reasonLateApology,
    required this.reasonNewGuest,
    required this.reasonOther,
    required this.noteLabel,
    required this.confirmAddCta,
    required this.rewardAddedToast,
    required this.visitDialogTitle,
    required this.visitFieldSpend,
    required this.visitErrorSpend,
    required this.visitConfirmCta,
    required this.cancel,
    required this.visitOkToast,
    required this.visitPendingToast,
    required this.activityLogTitle,
    required this.activityEmpty,
    required this.activityRewardLine,
    required this.activityVisitLine,
    required this.loadFailed,
    required this.retryCta,
    required this.lockTitle,
    required this.lockHint,
    required this.errorGeneric,
  });

  final String screenTitle;

  /// Large search field hint (name or phone fragment).
  final String searchHint;
  final String recentTitle;
  final String noResults;

  /// Shown before anything was searched.
  final String emptyTermHint;

  // Stats grid on the result card (Western digits substituted in).
  final String statsPoints;
  final String statsStamps;

  /// Stamp fraction, e.g. `3 من 10`.
  final String statsStampsOfTemplate;
  final String statsVisits;

  final String tierBronze;
  final String tierSilver;
  final String tierGold;

  final String recentOrdersTitle;
  final String recentOrdersEmpty;

  /// `{total}` rendered as `95 ج.م`-style line.
  final String totalTemplate;

  final String addRewardCta;
  final String registerVisitCta;

  // Manual reward bottom sheet.
  final String rewardSheetTitle;
  final String rewardPoints25;
  final String rewardFreeDrink;
  final String rewardFreeTopping;
  final String reasonLabel;
  final String reasonLateApology;
  final String reasonNewGuest;
  final String reasonOther;
  final String noteLabel;
  final String confirmAddCta;

  /// تمت الإضافة ✓
  final String rewardAddedToast;

  // Register-visit spend dialog.
  final String visitDialogTitle;
  final String visitFieldSpend;
  final String visitErrorSpend;
  final String visitConfirmCta;
  final String cancel;

  /// Visit recorded AND stamp written (or below threshold).
  final String visitOkToast;

  /// Visit recorded but loyalty_state RLS blocked the direct stamp write —
  /// identical copy to the staff board pending toast (#012).
  final String visitPendingToast;

  // Activity log sheet (staff_log rows for this phone).
  final String activityLogTitle;
  final String activityEmpty;

  /// `{reward}` + `{reason}` summary line of a manual_reward entry.
  final String activityRewardLine;
  final String activityVisitLine;

  final String loadFailed;
  final String retryCta;
  final String lockTitle;

  /// Pointer to the elevation SQL in docs/SUPABASE_SETUP.md (§Elevate) —
  /// same copy as the staff board lock panel.
  final String lockHint;
  final String errorGeneric;

  static const LookupStrings _ar = LookupStrings(
    screenTitle: 'حساب العميل',
    searchHint: 'اكتب الاسم أو رقم الهاتف',
    recentTitle: 'بحث سابق',
    noResults: 'مفيش نتايج مطابقة',
    emptyTermHint: 'ابحث بالاسم أو رقم الموبايل عن عميل',
    statsPoints: 'النقاط',
    statsStamps: 'الأختام',
    statsStampsOfTemplate: '{have} من 10',
    statsVisits: 'الزيارات',
    tierBronze: 'برونزي',
    tierSilver: 'فضي',
    tierGold: 'دهبي',
    recentOrdersTitle: 'آخر الطلبات',
    recentOrdersEmpty: 'لا طلبات بعد',
    totalTemplate: '{total} ج.م',
    addRewardCta: 'إضافة مكافأة',
    registerVisitCta: 'تسجيل زيارة',
    rewardSheetTitle: 'إضافة مكافأة يدوية',
    rewardPoints25: '+25 نقطة',
    rewardFreeDrink: 'مشروب مجاني',
    rewardFreeTopping: 'توبينج مجاني',
    reasonLabel: 'السبب',
    reasonLateApology: 'اعتذار عن تأخير',
    reasonNewGuest: 'ضيف جديد',
    reasonOther: 'أخرى',
    noteLabel: 'ملاحظة (اختياري)',
    confirmAddCta: 'تأكيد الإضافة',
    rewardAddedToast: 'تمت الإضافة ✓',
    visitDialogTitle: 'تسجيل زيارة للعميل',
    visitFieldSpend: 'المبلغ المنفق (جنيه)',
    visitErrorSpend: 'اكتب مبلغ صحيح',
    visitConfirmCta: 'تسجيل الزيارة',
    cancel: 'إلغاء',
    visitOkToast: 'الزيارة اتسجلت ✅',
    visitPendingToast: 'الزيارة اتسجلت — الختم يتضاف تلقائيًا قريبًا',
    activityLogTitle: 'سجل النشاط',
    activityEmpty: 'مفيش نشاط مسجل',
    activityRewardLine: 'مكافأة: {reward} — {reason}',
    activityVisitLine: 'زيارة مسجلة',
    loadFailed: 'حصلت مشكلة في تحميل الحساب',
    retryCta: 'إعادة المحاولة',
    lockTitle: 'قفل 🔒 بلا صلاحية موظف',
    lockHint: 'شغّل SQL ترقية الحساب من docs/SUPABASE_SETUP.md',
    errorGeneric: 'حصل خطأ، حاول تاني',
  );

  static const LookupStrings _en = LookupStrings(
    screenTitle: 'Customer account',
    searchHint: 'Type a name or phone number',
    recentTitle: 'Recent searches',
    noResults: 'No matching customers',
    emptyTermHint: 'Search a customer by name or phone number',
    statsPoints: 'Points',
    statsStamps: 'Stamps',
    statsStampsOfTemplate: '{have} of 10',
    statsVisits: 'Visits',
    tierBronze: 'Bronze',
    tierSilver: 'Silver',
    tierGold: 'Gold',
    recentOrdersTitle: 'Recent orders',
    recentOrdersEmpty: 'No orders yet',
    totalTemplate: '{total} EGP',
    addRewardCta: 'Add reward',
    registerVisitCta: 'Record visit',
    rewardSheetTitle: 'Grant manual reward',
    rewardPoints25: '+25 points',
    rewardFreeDrink: 'Free drink',
    rewardFreeTopping: 'Free topping',
    reasonLabel: 'Reason',
    reasonLateApology: 'Delay apology',
    reasonNewGuest: 'New guest',
    reasonOther: 'Other',
    noteLabel: 'Note (optional)',
    confirmAddCta: 'Confirm grant',
    rewardAddedToast: 'Added ✓',
    visitDialogTitle: 'Record customer visit',
    visitFieldSpend: 'Amount spent (EGP)',
    visitErrorSpend: 'Enter a valid amount',
    visitConfirmCta: 'Record visit',
    cancel: 'Cancel',
    visitOkToast: 'Visit recorded ✅',
    visitPendingToast: 'Visit recorded — the stamp will be added automatically soon',
    activityLogTitle: 'Activity log',
    activityEmpty: 'No recorded activity',
    activityRewardLine: 'Reward: {reward} — {reason}',
    activityVisitLine: 'Visit recorded',
    loadFailed: "Couldn't load the account",
    retryCta: 'Retry',
    lockTitle: 'Locked 🔒 no staff permission',
    lockHint: 'Run the account-elevation SQL from docs/SUPABASE_SETUP.md',
    errorGeneric: 'Something went wrong, try again',
  );

  static LookupStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;

  String stampsOf(int have) =>
      statsStampsOfTemplate.replaceAll('{have}', '$have');

  String total(int egp) => totalTemplate.replaceAll('{total}', '$egp');

  String activityReward(String reward, String reason) => activityRewardLine
      .replaceAll('{reward}', reward)
      .replaceAll('{reason}', reason);
}
