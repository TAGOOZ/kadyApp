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
    oddsFootnote: 'الاحتمالات: ٣٠٪ نقاط ٥ · ٢٥٪ نقاط ١٠ · ٢٠٪ توبينج · ١٠٪ ضعف · ١٥٪ حظ أوفر',
    termsButton: 'الشروط والاحتمالات',
    termsTitle: 'الشروط والاحتمالات',
    termsBody:
        '• كل لفة تستهلك توكن واحد (كل ٣ أختام = توكن).\n'
        '• الاحتمالات الحالية: ٣٠٪ ٥ نقاط، ٢٥٪ ١٠ نقاط، ٢٠٪ توبينج مجاني، ١٠٪ ضعف الطلب الجاي، ١٥٪ حظ أوفر.\n'
        '• الجوائز العينية (توبينج/مشروب) لها مخزون محدود؛ عند النفاد يُعاد توزيع الاحتمالات على الجوائز المتاحة.\n'
        '• التوبينج/المشروب صالح ١٤ يوم، السناك من البطاقة ٣٠ يوم. منتهي لا يُسترد.\n'
        '• لا يمكن ربح أكثر من ٥ لفات/دقيقة (حد حماية).\n'
        '• طريقة مجانية للمشاركة: تواصل مع الإدارة للحصول على توكن مجاني (بدون شراء) — حسب القانون المصري.',
    expiryNote: 'الجوائز صالحة ١٤ يوم (السناك ٣٠ يوم)',
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
    oddsFootnote: 'Odds: 30% 5 pts · 25% 10 pts · 20% topping · 10% double · 15% try again',
    termsButton: 'Terms & odds',
    termsTitle: 'Terms & odds',
    termsBody:
        '• Each spin consumes 1 token (3 stamps = 1 token).\n'
        '• Current odds: 30% 5 pts, 25% 10 pts, 20% free topping, 10% double next, 15% try again.\n'
        '• Physical prizes (topping/drink) have limited inventory; when exhausted odds renormalize.\n'
        '• Topping/drink valid 14 days, snack 30 days. Expired not redeemable.\n'
        '• Max 5 spins/min.\n'
        '• No-purchase entry: ask staff for a free token (per Egyptian law).',
    expiryNote: 'Prizes valid 14 days (snack 30 days)',
  );

  static SpinnerStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
