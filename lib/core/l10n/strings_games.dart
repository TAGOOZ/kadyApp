// Shared strings for the games hub (game screens ship their own catalogs).
import 'app_strings.dart';

class GamesStrings {
  const GamesStrings({
    required this.hubTitle,
    required this.hubSubtitle,
    required this.spinnerTitle,
    required this.spinnerLockedHint,
    required this.matchTitle,
    required this.matchLockedHint,
    required this.scratchTitle,
    required this.scratchLockedHint,
    required this.questsTitle,
    required this.questsHint,
    required this.play,
  });

  final String hubTitle;
  final String hubSubtitle;
  final String spinnerTitle;
  final String spinnerLockedHint;
  final String matchTitle;
  final String matchLockedHint;
  final String scratchTitle;
  final String scratchLockedHint;
  final String questsTitle;
  final String questsHint;
  final String play;

  static const GamesStrings _ar = GamesStrings(
    hubTitle: 'الألعاب',
    hubSubtitle: 'العب واكسب نقاط ومكافآت',
    spinnerTitle: 'دولاب الحظ',
    spinnerLockedHint: 'بتكسب توكن كل ٣ أختام',
    matchTitle: 'لعبة الأوراق',
    matchLockedHint: 'متاحة بعد إكمال بطاقة الأختام',
    scratchTitle: 'اكشط واكسب',
    scratchLockedHint: 'بطاقات الحملات والمناسبات',
    questsTitle: 'المهام والشارات',
    questsHint: 'كمّل مهام واكسب أكتر',
    play: 'العب!',
  );

  static const GamesStrings _en = GamesStrings(
    hubTitle: 'Games',
    hubSubtitle: 'Play to earn points and rewards',
    spinnerTitle: 'Spinner of Luck',
    spinnerLockedHint: 'Earn a token every 3 stamps',
    matchTitle: 'Card Match',
    matchLockedHint: 'Unlocks after completing a stamp card',
    scratchTitle: 'Scratch & Win',
    scratchLockedHint: 'Campaign and event cards',
    questsTitle: 'Quests & Badges',
    questsHint: 'Complete quests to earn more',
    play: 'Play!',
  );

  static GamesStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
