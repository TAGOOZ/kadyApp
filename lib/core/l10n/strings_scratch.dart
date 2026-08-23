// Strings for the Scratch & Win screen (#009) — Arabic-first, RTL-safe.
// Locked hint lives in the shared games catalog (GamesStrings.scratchLockedHint).
import 'app_strings.dart';

class ScratchStrings {
  const ScratchStrings({
    required this.screenTitle,
    required this.tokenChipPrefix,
    required this.lockedTitle,
    required this.scratchHint,
    required this.claimButton,
    required this.laterButton,
    required this.upcomingCaption,
    required this.validChip,
    required this.voucherHint,
    required this.campaignChip,
    required this.resultWinTitle,
    required this.resultNothingTitle,
    required this.noTokenSnackbar,
  });

  final String screenTitle;
  final String tokenChipPrefix;
  final String lockedTitle;

  /// `اسحب إصبعك فوق البطاقة`.
  final String scratchHint;
  final String claimButton;
  final String laterButton;

  /// Caption under the locked upcoming thumbnails.
  final String upcomingCaption;

  /// `صالحة` chip on voucher prizes + where to use them.
  final String validChip;
  final String voucherHint;

  /// Campaign badge chip (`عرض ليالي الماتش 🔥`) — shown only while an active
  /// match_night campaign row exists.
  final String campaignChip;

  final String resultWinTitle;
  final String resultNothingTitle;
  final String noTokenSnackbar;

  static const ScratchStrings _ar = ScratchStrings(
    screenTitle: 'اكشط واكسب',
    tokenChipPrefix: 'توكنات',
    lockedTitle: 'البطاقة مقفولة لحد ما تكسب توكن',
    scratchHint: 'اسحب إصبعك فوق البطاقة',
    claimButton: 'استلم المكافأة',
    laterButton: 'لاحقاً',
    upcomingCaption: 'بطاقة قادمة',
    validChip: 'صالحة',
    voucherHint: 'تُستخدم في الكافيه',
    campaignChip: 'عرض ليالي الماتش 🔥',
    resultWinTitle: 'مبروك 🎉',
    resultNothingTitle: 'حظ أوفر',
    noTokenSnackbar: 'مفيش توكن',
  );

  static const ScratchStrings _en = ScratchStrings(
    screenTitle: 'Scratch & Win',
    tokenChipPrefix: 'Tokens',
    lockedTitle: 'Locked until you earn a token',
    scratchHint: 'Drag your finger across the card',
    claimButton: 'Claim reward',
    laterButton: 'Later',
    upcomingCaption: 'Upcoming card',
    validChip: 'Valid',
    voucherHint: 'Redeem at the café',
    campaignChip: 'Match Nights 🔥',
    resultWinTitle: 'Congrats! 🎉',
    resultNothingTitle: 'Better luck next time',
    noTokenSnackbar: 'No tokens available',
  );

  static ScratchStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
