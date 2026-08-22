// Strings for the 3-Card Match screen (#009) — Arabic-first, RTL-safe.
// Locked hint lives in the shared games catalog (GamesStrings.matchLockedHint).
import 'app_strings.dart';

class MatchStrings {
  const MatchStrings({
    required this.screenTitle,
    required this.tokenChipPrefix,
    required this.lockedTitle,
    required this.lockedFootnote,
    required this.attemptsPrefix,
    required this.legendTwo,
    required this.legendThree,
    required this.roundHint,
    required this.resultWinTitle,
    required this.resultNothingTitle,
    required this.twoMatchLabel,
    required this.threeMatchLabel,
    required this.claimButton,
    required this.noTokenSnackbar,
  });

  final String screenTitle;
  final String tokenChipPrefix;
  final String lockedTitle;
  final String lockedFootnote;
  final String attemptsPrefix;

  /// Reward legend shown under the cards.
  final String legendTwo;
  final String legendThree;

  final String roundHint;
  final String resultWinTitle;
  final String resultNothingTitle;
  final String twoMatchLabel;
  final String threeMatchLabel;
  final String claimButton;
  final String noTokenSnackbar;

  /// `محاولات: n` — Arabic-Indic numerals per the slice spec copy.
  static const _arDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  String attempts(int count) =>
      '$attemptsPrefix: ${count.toString().split('').map((d) => _arDigits[int.parse(d)]).join()}';

  static const MatchStrings _ar = MatchStrings(
    screenTitle: 'لعبة الأوراق',
    tokenChipPrefix: 'توكنات',
    lockedTitle: 'اللعبة مقفولة لحد ما تكسب توكن',
    lockedFootnote: 'متاحة بعد إكمال بطاقة الأختام',
    attemptsPrefix: 'محاولات',
    legendTwo: 'مطابقة ٢ → ٥ نقاط',
    legendThree: 'مطابقة ٣ → مشروب مجاني (نادرة)',
    roundHint: 'اضغط على الكروت واحد واحد لتكشفها',
    resultWinTitle: 'مبروك 🎉',
    resultNothingTitle: 'حظ أوفر',
    twoMatchLabel: 'مطابقة ٢ — ٥ نقاط',
    threeMatchLabel: 'مطابقة ٣ — مشروب مجاني!',
    claimButton: 'تمام',
    noTokenSnackbar: 'مفيش توكن',
  );

  static const MatchStrings _en = MatchStrings(
    screenTitle: 'Card Match',
    tokenChipPrefix: 'Tokens',
    lockedTitle: 'Locked until you earn a token',
    lockedFootnote: 'Unlocks after completing a stamp card',
    attemptsPrefix: 'Attempts',
    legendTwo: 'Match 2 → 5 points',
    legendThree: 'Match 3 → free drink (rare)',
    roundHint: 'Tap the cards one by one to reveal them',
    resultWinTitle: 'Congrats! 🎉',
    resultNothingTitle: 'Better luck next time',
    twoMatchLabel: 'Match of 2 — 5 points',
    threeMatchLabel: 'Match of 3 — free drink!',
    claimButton: 'OK',
    noTokenSnackbar: 'No tokens available',
  );

  static MatchStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
