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
  );

  static SpinnerStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
