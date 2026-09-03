// Strings for the Spinner of Luck screen (#008) — Arabic-first, RTL-safe.
// Counts are interpolated with Western digits; prize labels live in the
// engine (spinner_engine.dart) so wheel slices and modal stay in sync.
import 'app_strings.dart';

class SpinnerStrings {
  const SpinnerStrings({
    required this.screenTitle,
    required this.tokenChipPrefix,
    required this.spinButton,
    required this.lockedTitle,
    required this.lockedFootnote,
    required this.resultWinTitle,
    required this.resultNothingTitle,
    required this.claimButton,
    required this.noTokenSnackbar,
    required this.oddsFootnote,
    required this.termsButton,
    required this.termsTitle,
    required this.termsBody,
    required this.expiryNote,
    required this.freeTokenButton,
    required this.freeTokenSuccess,
    required this.freeTokenRateLimited,
    required this.freeTokenCapReached,
  });

  final String screenTitle;
  final String tokenChipPrefix;
  final String spinButton;
  final String lockedTitle;
  final String lockedFootnote;
  final String resultWinTitle;
  final String resultNothingTitle;
  final String claimButton;
  final String noTokenSnackbar;
  final String oddsFootnote;
  final String termsButton;
  final String termsTitle;
  final String termsBody;
  final String expiryNote;
  final String freeTokenButton;
  final String freeTokenSuccess;
  final String freeTokenRateLimited;
  final String freeTokenCapReached;

  /// `توكنات: n` — Western digits per spec.
  String tokenChip(int count) => '$tokenChipPrefix: $count';

  static const SpinnerStrings _ar = SpinnerStrings(
    screenTitle: 'دولاب الحظ',
    tokenChipPrefix: 'توكنات',
    spinButton: 'لفّ!',
    lockedTitle: 'الدولاب مقفول لحد ما تكسب توكن',
    lockedFootnote: 'بتكسب توكن كل ٣ أختام ☕',
    resultWinTitle: 'مبروك! 🎉',
    resultNothingTitle: 'حظ أوفر المرة الجاية 😅',
    claimButton: 'تمام',
    noTokenSnackbar: 'مفيش توكن',
    oddsFootnote: 'الاحتمالات: ٣٠٪ نقاط ٥ · ٢٥٪ نقاط ١٠ · ١٥٪ توبينج · ١٠٪ ضعف · ٥٪ مشروب · ١٥٪ حظ أوفر (٨٥٪ فوز، ٢٠٪ عينية)',
    termsButton: 'الشروط والاحتمالات',
    termsTitle: 'الشروط والاحتمالات',
    termsBody:
        '• كل لفة تستهلك توكن واحد (كل ٣ أختام = توكن، سقف ٥ توكن، التوكن صالح ٣٠ يوم).\n'
        '• الاحتمالات الحالية (٧ شرائح): ٣٠٪ ٥ نقاط، ٢٥٪ ١٠ نقاط، ١٥٪ توبينج مجاني، ١٠٪ ضعف الطلب الجاي (سقف +١٠ نقاط إضافية، صالح ٧ أيام)، ٥٪ مشروب مجاني نادر، ١٥٪ حظ أوفر.\n'
        '• الجوائز العينية (توبينج/مشروب/ضعف) لها مخزون محدود؛ عند النفاد يُعاد توزيع الاحتمالات على الجوائز المتاحة، ولو نفد قبل اللف سيُرجع التوكن (sold_out).\n'
        '• التوبينج/المشروب صالح ١٤ يوم، السناك من البطاقة ٣٠ يوم، ضعف ٧ أيام. منتهي لا يُسترد.\n'
        '• حماية: ٥ لفات/دقيقة، ٣ لفات/يوم، سقف ٥ توكن، قفل تحكم لمنع التلاعب، كشف أجهزة متعددة.\n'
        '• طريقة مجانية للمشاركة: اضغط "توكن مجاني" للحصول على توكن بدون شراء (مرة كل ٧ أيام، ٣ لكل جهاز/٣٠ يوم) — حسب القانون المصري.\n'
        '• الشروط: ١٦+ سنة، موظفو الكافيه وعائلاتهم غير مؤهلين، الجائزة غير قابلة للتحويل/الاستبدال نقداً، يُسمح بالاستبدال لمكافئ عند النفاد.',
    expiryNote: 'الجوائز صالحة ١٤ يوم (السناك ٣٠ يوم)',
    freeTokenButton: 'توكن مجاني',
    freeTokenSuccess: 'تم إضافة توكن مجاني! 🎉',
    freeTokenRateLimited: 'حصلت على توكن مجاني هذا الأسبوع — حاول بعد ٧ أيام',
    freeTokenCapReached: 'وصلت للحد الأقصى ٥ توكن',
  );

  static const SpinnerStrings _en = SpinnerStrings(
    screenTitle: 'Spinner of Luck',
    tokenChipPrefix: 'Tokens',
    spinButton: 'Spin!',
    lockedTitle: 'Locked until you earn a token',
    lockedFootnote: 'You earn a token every 3 stamps ☕',
    resultWinTitle: 'Congrats! 🎉',
    resultNothingTitle: 'Better luck next time 😅',
    claimButton: 'OK',
    noTokenSnackbar: 'No tokens available',
    oddsFootnote: 'Odds: 30% 5 pts · 25% 10 pts · 15% topping · 10% double · 5% drink · 15% try again (85% win, 20% voucher)',
    termsButton: 'Terms & odds',
    termsTitle: 'Terms & odds',
    termsBody:
        '• Each spin consumes 1 token (3 stamps = 1 token, cap 5, token valid 30 days).\n'
        '• Current odds (7 slices): 30% 5 pts, 25% 10 pts, 15% free topping, 10% double next (capped +10 pts, valid 7 days), 5% rare free drink, 15% try again.\n'
        '• Physical prizes (topping/drink/double) have limited inventory; when exhausted odds renormalize, and if sold out before spin token is refunded (sold_out).\n'
        '• Topping/drink valid 14 days, snack 30 days, double 7 days. Expired not redeemable.\n'
        '• Limits: 5 spins/min, 3/day, 5 tokens max, advisory lock, device farm check.\n'
        '• No-purchase entry: tap "Free token" for 1 free token every 7 days (3 per device/30d, per Egyptian law).\n'
        '• Eligibility: 16+, staff & family excluded, non-transferable, no cash alternative, substitution allowed when sold out.',
    expiryNote: 'Prizes valid 14 days (snack 30 days)',
    freeTokenButton: 'Free token',
    freeTokenSuccess: 'Free token added! 🎉',
    freeTokenRateLimited: 'You claimed a free token this week — try after 7 days',
    freeTokenCapReached: 'Token cap reached (5 max)',
  );

  static SpinnerStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
