// Strings for the Spinner of Luck screen (#008 / FEATURES §S7) — Arabic-first,
// RTL-safe. Locked hint lives in the shared games catalog
// (GamesStrings.spinnerLockedHint).
import 'app_strings.dart';

class SpinnerStrings {
  const SpinnerStrings({
    required this.screenTitle,
    required this.tokenChipPrefix,
    required this.spinButton,
    required this.spinningLabel,
    required this.lockedTitle,
    required this.roundHint,
    required this.legendTitle,
    required this.claimButton,
    required this.resultWinTitle,
    required this.resultNothingTitle,
    required this.noTokenSnackbar,
  });

  final String screenTitle;
  final String tokenChipPrefix;
  final String spinButton;

  /// Shown on the button while the wheel is animating.
  final String spinningLabel;
  final String lockedTitle;

  /// Hint under the wheel while a round can start.
  final String roundHint;

  /// Heading of the prize-pool legend card.
  final String legendTitle;
  final String claimButton;
  final String resultWinTitle;
  final String resultNothingTitle;
  final String noTokenSnackbar;

  static const SpinnerStrings _ar = SpinnerStrings(
    screenTitle: 'دولاب الحظ',
    tokenChipPrefix: 'توكنات',
    spinButton: 'لفّ الدولاب',
    spinningLabel: 'بيلف…',
    lockedTitle: 'الدولاب مقفول لحد ما تكسب توكن',
    roundHint: 'كل لفّة توكن واحد — حظ سعيد',
    legendTitle: 'جوايز الدولاب',
    claimButton: 'استلم المكافأة',
    resultWinTitle: 'مبروك 🎉',
    resultNothingTitle: 'حظ أوفر',
    noTokenSnackbar: 'مفيش توكن',
  );

  static const SpinnerStrings _en = SpinnerStrings(
    screenTitle: 'Spinner of Luck',
    tokenChipPrefix: 'Tokens',
    spinButton: 'Spin the wheel',
    spinningLabel: 'Spinning…',
    lockedTitle: 'Locked until you earn a token',
    roundHint: 'One token per spin — good luck',
    legendTitle: 'Wheel prizes',
    claimButton: 'Claim reward',
    resultWinTitle: 'Congrats! 🎉',
    resultNothingTitle: 'Better luck next time',
    noTokenSnackbar: 'No tokens available',
  );

  static SpinnerStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
