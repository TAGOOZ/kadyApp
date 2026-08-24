// Home hub copy (#005), keyed by AppLang (mirrors AppStrings pattern).
// Numerals decision §11.11: Western `0123` in both languages.
import 'app_strings.dart';
import '../../domain/loyalty_controller.dart';

class HomeStrings {
  const HomeStrings({
    required this.greetingSignedInTemplate,
    required this.greetingGeneric,
    required this.comingSoon,
    required this.pointsSuffix,
    required this.pointsProgressTemplate,
    required this.freeDrinkCaption,
    required this.devBoostCardLabel,
    required this.devBoostSheetTitle,
    required this.devBoostApplyLabel,
    required this.devBoostApplied,
    required this.stampCaptionTemplate,
    required this.completedCardsBadgeTemplate,
    required this.actionOrderNow,
    required this.actionScanEarn,
    required this.actionPlay,
    required this.actionRewards,
    required this.bannerMatchNightsTitle,
    required this.bannerMatchNightsBody,
    required this.bannerExamSeasonTitle,
    required this.bannerExamSeasonBody,
    required this.bannerRamadanTitle,
    required this.bannerRamadanBody,
    required this.activeOrderTemplate,
    required this.statusNew,
    required this.statusAccepted,
    required this.statusInPrep,
    required this.statusReady,
    required this.statusOutForDelivery,
    required this.registerLink,
    required this.tierBronze,
    required this.tierSilver,
    required this.tierGold,
    required this.rewardsSectionTitle,
    required this.browseMenuTitle,
    required this.orderAgainTitle,
    required this.lastOrderTemplate,
    required this.actionMyOrders,
  });

  final String greetingSignedInTemplate;
  final String greetingGeneric;
  final String comingSoon;
  final String pointsSuffix;
  final String pointsProgressTemplate;
  final String freeDrinkCaption;
  final String devBoostCardLabel;
  final String devBoostSheetTitle;
  final String devBoostApplyLabel;
  final String devBoostApplied;
  final String stampCaptionTemplate;
  final String completedCardsBadgeTemplate;
  final String actionOrderNow;
  final String actionScanEarn;
  final String actionPlay;
  final String actionRewards;
  final String bannerMatchNightsTitle;
  final String bannerMatchNightsBody;
  final String bannerExamSeasonTitle;
  final String bannerExamSeasonBody;
  final String bannerRamadanTitle;
  final String bannerRamadanBody;
  final String activeOrderTemplate;
  final String statusNew;
  final String statusAccepted;
  final String statusInPrep;
  final String statusReady;
  final String statusOutForDelivery;
  final String registerLink;
  final String tierBronze;
  final String tierSilver;
  final String tierGold;

  /// Loyalty hero card header (merged points + stamps).
  final String rewardsSectionTitle;

  /// Home category shortcuts section header.
  final String browseMenuTitle;

  /// Order-again strip section header.
  final String orderAgainTitle;

  /// `آخر طلبك #NNNN`
  final String lastOrderTemplate;

  /// Quick-action tile → /orders.
  final String actionMyOrders;

  /// `أهلاً {firstName} 👋`
  String greeting(String firstName) =>
      greetingSignedInTemplate.replaceAll('{name}', firstName);

  /// `{points} / {goal}` — next free-drink threshold.
  String pointsProgress(int points, int goal) => pointsProgressTemplate
      .replaceAll('{points}', '$points')
      .replaceAll('{goal}', '$goal');

  /// `{stamps} / 10 زيارة → سناكس مجاني`
  String stampCaption(int stamps) =>
      stampCaptionTemplate.replaceAll('{stamps}', '$stamps');

  /// Badge for fully-earned cards awaiting redemption.
  String completedCardsBadge(int count) =>
      completedCardsBadgeTemplate.replaceAll('{count}', '$count');

  /// `طلبك #NNNN — {status}`
  String activeOrder(int displayNumber, String statusAr) =>
      activeOrderTemplate
          .replaceAll('{number}', '$displayNumber')
          .replaceAll('{status}', statusAr);

  /// `آخر طلبك #NNNN`
  String lastOrder(int displayNumber) =>
      lastOrderTemplate.replaceAll('{number}', '$displayNumber');

  /// DB check-constraint vocabulary → Arabic label; falls back to the raw wire.
  String statusLabel(String wire) => switch (wire) {
        'new' => statusNew,
        'accepted' => statusAccepted,
        'in_prep' => statusInPrep,
        'ready' => statusReady,
        'out_for_delivery' => statusOutForDelivery,
        _ => wire,
      };

  /// Tier label per lifetime tier.
  String tierLabel(Tier? tier) => switch (tier) {
        Tier.silver => tierSilver,
        Tier.gold => tierGold,
        _ => tierBronze,
      };

  /// Banner titles/bodies zipped into display order (match nights first per #005).
  List<(String, String)> get banners => [
        (bannerMatchNightsTitle, bannerMatchNightsBody),
        (bannerExamSeasonTitle, bannerExamSeasonBody),
        (bannerRamadanTitle, bannerRamadanBody),
      ];
}

abstract final class HomeStringsCatalog {
  static const Map<AppLang, HomeStrings> values = {
    AppLang.ar: HomeStrings(
      greetingSignedInTemplate: 'أهلاً {name} 👋',
      greetingGeneric: 'أهلاً بيك في القاضي',
      comingSoon: 'قريبًا',
      pointsSuffix: 'نقطة',
      pointsProgressTemplate: '{points} / {goal}',
      freeDrinkCaption: '→ مشروب مجاني',
      devBoostCardLabel: 'تجربة',
      devBoostSheetTitle: 'أدوات تجريبية (ديف)',
      devBoostApplyLabel: 'تجربة: زوّد نقطة وطابع',
      devBoostApplied: 'اتضاف ✅',
      stampCaptionTemplate: '{stamps} / 10 زيارة → سناكس مجاني',
      completedCardsBadgeTemplate: '{count} بطاقة مكتملة',
      actionOrderNow: 'اطلب دلوقتي',
      actionScanEarn: 'امسح واكسب',
      actionPlay: 'العب',
      actionRewards: 'المكافآت',
      bannerMatchNightsTitle: 'ليالي الماتش',
      bannerMatchNightsBody: 'نقاط مضاعفة',
      bannerExamSeasonTitle: 'موسم الامتحانات',
      bannerExamSeasonBody: 'بندل الطلبة',
      bannerRamadanTitle: 'كويست رمضان',
      bannerRamadanBody: 'مهام يومية ومكافآت',
      activeOrderTemplate: 'طلبك #{number} — {status}',
      statusNew: 'قيد الاستلام',
      statusAccepted: 'مقبول',
      statusInPrep: 'قيد التحضير',
      statusReady: 'جاهز',
      statusOutForDelivery: 'في الطريق إليك',
      registerLink: 'سجّل بحساب Google',
      tierBronze: 'برونزي',
      tierSilver: 'فضي',
      tierGold: 'ذهبي',
      rewardsSectionTitle: 'مكافآتك',
      browseMenuTitle: 'تصفح المنيو',
      orderAgainTitle: 'اطلب تاني',
      lastOrderTemplate: 'آخر طلبك #{number}',
      actionMyOrders: 'طلباتي',
    ),
    AppLang.en: HomeStrings(
      greetingSignedInTemplate: 'Hi {name} 👋',
      greetingGeneric: 'Welcome to Elkady Café',
      comingSoon: 'Coming soon',
      pointsSuffix: 'pts',
      pointsProgressTemplate: '{points} / {goal}',
      freeDrinkCaption: '→ Free drink',
      devBoostCardLabel: 'Dev demo',
      devBoostSheetTitle: 'Dev tools (debug)',
      devBoostApplyLabel: 'Demo: add a point & stamp',
      devBoostApplied: 'Applied ✅',
      stampCaptionTemplate: '{stamps} / 10 visits → Free snack',
      completedCardsBadgeTemplate: '{count} completed card(s)',
      actionOrderNow: 'Order now',
      actionScanEarn: 'Scan & earn',
      actionPlay: 'Play',
      actionRewards: 'Rewards',
      bannerMatchNightsTitle: 'Match Nights',
      bannerMatchNightsBody: 'Double points',
      bannerExamSeasonTitle: 'Exam Season',
      bannerExamSeasonBody: 'Student bundle',
      bannerRamadanTitle: 'Ramadan Quest',
      bannerRamadanBody: 'Daily quests & rewards',
      activeOrderTemplate: 'Order #{number} — {status}',
      statusNew: 'Received',
      statusAccepted: 'Accepted',
      statusInPrep: 'In preparation',
      statusReady: 'Ready',
      statusOutForDelivery: 'On the way',
      registerLink: 'Sign in with Google',
      tierBronze: 'Bronze',
      tierSilver: 'Silver',
      tierGold: 'Gold',
      rewardsSectionTitle: 'Your rewards',
      browseMenuTitle: 'Browse the menu',
      orderAgainTitle: 'Order again',
      lastOrderTemplate: 'Last order #{number}',
      actionMyOrders: 'My orders',
    ),
  };

  static HomeStrings of(AppLang lang) => values[lang]!;
}
