// Quests & badges strings catalog (#010) — mirrors the AppStrings pattern
// (`app_strings.dart` is intentionally NOT edited; this file owns all
// user-facing copy for the quests/badges screen). ar default, en toggle.
//
// Numerals: the slice spec asks for AR-Indic numerals in progress labels,
// deadline and reward chips — [QuestsStrings.numerals] converts when the
// active language is Arabic (Western digits stay for English).
import 'app_strings.dart';

class QuestsStrings {
  const QuestsStrings({
    required this.screenTitle,
    required this.tabQuests,
    required this.tabBadges,
    required this.claimButton,
    required this.claimedLabel,
    required this.rewardPointsTemplate,
    required this.rewardMatchToken,
    required this.rewardBonusStamp,
    required this.deadlineMonthLabel,
    required this.deadlineWeekLabel,
    required this.loadFailed,
    required this.retryCta,
    required this.emptyHint,
    required this.newBadgeBanner,
    required this.pointsClaimedTemplate,
    required this.tokenQueuedSnackbar,
    required this.stampQueuedSnackbar,
    required this.bottomBanner,
    required this.badgeTitlesAr,
    required this.badgeTitlesEn,
  });

  final String screenTitle;
  final String tabQuests;
  final String tabBadges;

  /// Claim CTA on a completed, unclaimed quest card.
  final String claimButton;
  final String claimedLabel;

  /// `{n}` → points amount.
  final String rewardPointsTemplate;
  final String rewardMatchToken;
  final String rewardBonusStamp;

  /// نهاية الشهر / نهاية الأسبوع deadline chips.
  final String deadlineMonthLabel;
  final String deadlineWeekLabel;

  final String loadFailed;
  final String retryCta;
  final String emptyHint;

  /// One-time celebration when a badge newly unlocks.
  final String newBadgeBanner;

  /// `{n}` → +50 points confirmation.
  final String pointsClaimedTemplate;

  /// DEVIATION (#010): match token has no controller grant method yet —
  /// queued as a pending grant; user is told it lands with an upcoming
  /// update once `grantTokens()` exists in the shared seam.
  final String tokenQueuedSnackbar;

  /// Same deviation path for the extra-stamp reward.
  final String stampQueuedSnackbar;
  final String bottomBanner;

  /// Keyed by BadgeId.name for both languages.
  final Map<String, String> badgeTitlesAr;
  final Map<String, String> badgeTitlesEn;

  static const QuestsStrings _ar = QuestsStrings(
    screenTitle: 'المهام والشارات',
    tabQuests: 'المهام',
    tabBadges: 'الشارات',
    claimButton: 'استلم المكافأة',
    claimedLabel: 'تم الاستلام',
    rewardPointsTemplate: '+{n} نقطة',
    rewardMatchToken: 'توكن لعب',
    rewardBonusStamp: 'ختم إضافي',
    deadlineMonthLabel: 'نهاية الشهر',
    deadlineWeekLabel: 'نهاية الأسبوع',
    loadFailed: 'حصلت مشكلة في تحميل المهام',
    retryCta: 'إعادة المحاولة',
    emptyHint: 'كمّل طلبات وشوف تقدمك هنا',
    newBadgeBanner: 'مبروك! شارة جديدة 🎉',
    pointsClaimedTemplate: '+{n} نقطة اتضافت لحسابك!',
    tokenQueuedSnackbar: 'تم! التوكن يُضاف تلقائيًا قريبًا',
    stampQueuedSnackbar: 'تم! الختم يُضاف تلقائيًا قريبًا',
    bottomBanner: 'كمّل مهام أكتر واكسب أكتر',
    badgeTitlesAr: {
      'matchNightsClub': 'نادي ليالي الماتشات',
      'examWarrior': 'رياضي الامتحانات',
      'ramadanOwl': 'بومة رمضان',
      'goldLoyalist': 'عميل ذهبي',
    },
    badgeTitlesEn: {
      'matchNightsClub': 'Match Night Club',
      'examWarrior': 'Exam Warrior',
      'ramadanOwl': 'Ramadan Owl',
      'goldLoyalist': 'Gold Loyalist',
    },
  );

  static const QuestsStrings _en = QuestsStrings(
    screenTitle: 'Quests & Badges',
    tabQuests: 'Quests',
    tabBadges: 'Badges',
    claimButton: 'Claim reward',
    claimedLabel: 'Claimed',
    rewardPointsTemplate: '+{n} pts',
    rewardMatchToken: 'Match token',
    rewardBonusStamp: 'Bonus stamp',
    deadlineMonthLabel: 'Ends this month',
    deadlineWeekLabel: 'Ends this week',
    loadFailed: 'Failed to load quests',
    retryCta: 'Retry',
    emptyHint: 'Place orders and watch your progress here',
    newBadgeBanner: 'Congrats! New badge 🎉',
    pointsClaimedTemplate: '+{n} pts added to your account!',
    tokenQueuedSnackbar: 'Done! The token will be added automatically soon',
    stampQueuedSnackbar: 'Done! The stamp will be added automatically soon',
    bottomBanner: 'Complete more quests and earn more',
    badgeTitlesAr: {
      'matchNightsClub': 'نادي ليالي الماتشات',
      'examWarrior': 'رياضي الامتحانات',
      'ramadanOwl': 'بومة رمضان',
      'goldLoyalist': 'عميل ذهبي',
    },
    badgeTitlesEn: {
      'matchNightsClub': 'Match Night Club',
      'examWarrior': 'Exam Warrior',
      'ramadanOwl': 'Ramadan Owl',
      'goldLoyalist': 'Gold Loyalist',
    },
  );

  static QuestsStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;

  String badgeTitle(String badgeKey, AppLang lang) =>
      (lang == AppLang.ar ? badgeTitlesAr : badgeTitlesEn)[badgeKey] ?? badgeKey;

  /// Template fill helper (`{n}`).
  static String fill(String template, String n) =>
      template.replaceAll('{n}', n);

  /// AR-Indic numerals when Arabic; Western otherwise (slice #010 copy
  /// contract — app-wide §11.11 decision untouched).
  static String numerals(String value, AppLang lang) {
    if (lang != AppLang.ar) return value;
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return String.fromCharCodes(value.codeUnits.map((code) {
      final digit = code - 0x30; // '0'
      return (digit >= 0 && digit <= 9)
          ? arabic[digit].codeUnitAt(0)
          : code;
    }));
  }

  /// `٢/٣`-style progress label (western source digits converted per lang).
  static String progressLabel(int progress, int target, AppLang lang) =>
      numerals('$progress/$target', lang);
}
