// Checkout slice strings catalog — mirrors the AppStrings pattern
// (`app_strings.dart` is intentionally NOT edited; this file owns all
// user-facing copy for cart, mode selection, checkout and confirmation).
// ar default, en toggle. Numerals: Western 0123 in both languages.
import 'app_strings.dart';

class CheckoutStrings {
  const CheckoutStrings({
    required this.cartTitle,
    required this.emptyTitle,
    required this.emptyBody,
    required this.emptyCta,
    required this.continueCta,
    required this.removeTooltip,
    required this.decreaseTooltip,
    required this.increaseTooltip,
    required this.notesLabel,
    required this.notesHint,
    required this.modeSelectionTitle,
    required this.modeDineIn,
    required this.modePickup,
    required this.modeDelivery,
    required this.modeDineInHelper,
    required this.modePickupHelper,
    required this.modeDeliveryHelper,
    required this.checkoutTitle,
    required this.sectionDetails,
    required this.tableFieldLabel,
    required this.tableFieldHint,
    required this.areaInside,
    required this.areaTerrace,
    required this.orSeparator,
    required this.dineInMissingError,
    required this.slotNow,
    required this.pickupMissingError,
    required this.savedAddressesLabel,
    required this.noAddressesLine,
    required this.addAddressTitle,
    required this.labelHome,
    required this.labelWork,
    required this.labelOther,
    required this.addressLineLabel,
    required this.addressLineHint,
    required this.addAddressCta,
    required this.addressRequiredError,
    required this.addressSaveFailed,
    required this.subtotalRow,
    required this.deliveryFeeRow,
    required this.totalRow,
    required this.currencySuffix,
    required this.loyaltyBannerTemplate,
    required this.pointsBannerTemplate,
    required this.paymentCashHere,
    required this.paymentCashOnDelivery,
    required this.confirmCta,
    required this.submitFailed,
    required this.confirmedTitle,
    required this.etaPickup,
    required this.etaDelivery,
    required this.itemsSummaryTitle,
    required this.trackCta,
    required this.trackingSoonStub,
    required this.backHomeCta,
  });

  final String cartTitle;
  final String emptyTitle;
  final String emptyBody;
  final String emptyCta;
  final String continueCta;
  final String removeTooltip;
  final String decreaseTooltip;
  final String increaseTooltip;
  final String notesLabel;
  final String notesHint;

  final String modeSelectionTitle;
  final String modeDineIn;
  final String modePickup;
  final String modeDelivery;
  final String modeDineInHelper;
  final String modePickupHelper;
  final String modeDeliveryHelper;

  final String checkoutTitle;
  final String sectionDetails;
  final String tableFieldLabel;
  final String tableFieldHint;
  final String areaInside;
  final String areaTerrace;
  final String orSeparator;
  final String dineInMissingError;
  final String slotNow;
  final String pickupMissingError;
  final String savedAddressesLabel;
  final String noAddressesLine;
  final String addAddressTitle;
  final String labelHome;
  final String labelWork;
  final String labelOther;
  final String addressLineLabel;
  final String addressLineHint;
  final String addAddressCta;
  final String addressRequiredError;
  final String addressSaveFailed;

  final String subtotalRow;
  final String deliveryFeeRow;
  final String totalRow;
  final String currencySuffix;

  /// `{points}` is replaced with a Western-digit integer.
  final String loyaltyBannerTemplate;
  final String pointsBannerTemplate;
  final String paymentCashHere;
  final String paymentCashOnDelivery;
  final String confirmCta;
  final String submitFailed;

  final String confirmedTitle;

  /// `~10 دقائق استلام/صالة` · `~30 دقيقة توصيل`.
  final String etaPickup;
  final String etaDelivery;
  final String itemsSummaryTitle;
  final String trackCta;
  final String trackingSoonStub;
  final String backHomeCta;

  String egp(int valueEgp) => '$valueEgp $currencySuffix';

  String loyaltyBanner(int points) =>
      loyaltyBannerTemplate.replaceAll('{points}', '$points');

  String pointsBanner(int points) =>
      pointsBannerTemplate.replaceAll('{points}', '$points');

  String orderChip(int displayNumber) => '#$displayNumber';

  /// `HH:mm` — Western digits (§11.11), built from the Cairo wall clock.
  static String hhmm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

abstract final class CheckoutStringsCatalog {
  static const Map<AppLang, CheckoutStrings> values = {
    AppLang.ar: CheckoutStrings(
      cartTitle: 'السلة',
      emptyTitle: 'سلّتك فاضية',
      emptyBody: 'اختار حاجة حلوة من القائمة وابدأ تجمّع نقاط',
      emptyCta: 'تصفح القائمة',
      continueCta: 'متابعة الدفع',
      removeTooltip: 'إزالة من السلة',
      decreaseTooltip: 'تقليل الكمية',
      increaseTooltip: 'زيادة الكمية',
      notesLabel: 'ملاحظات الطلب',
      notesHint: 'أي تعليمات للطلب كله… مثال: بدون سكر في الكل',
      modeSelectionTitle: 'عايز تطلب إزاي؟',
      modeDineIn: 'صالة',
      modePickup: 'استلام',
      modeDelivery: 'توصيل',
      modeDineInHelper: 'سجّل دخول، اطلب من الترابيزة أو الكاونتر، واكسب نقاط',
      modePickupHelper: 'اطلب دلوقتي واستلم من كافيه القاضي',
      modeDeliveryHelper: 'اطلب لعنوانك. الدفع عند الاستلام',
      checkoutTitle: 'إتمام الطلب',
      sectionDetails: 'تفاصيل الطلب',
      tableFieldLabel: 'رقم الترابيزة',
      tableFieldHint: 'مثال: 12',
      areaInside: 'داخل',
      areaTerrace: 'تراس',
      orSeparator: 'أو',
      dineInMissingError: 'حدّد رقم الترابيزة أو المنطقة',
      slotNow: 'الآن',
      pickupMissingError: 'اختر وقت الاستلام',
      savedAddressesLabel: 'العناوين المحفوظة',
      noAddressesLine: 'مفيش عنوان محفوظ — ضيف عنوانك',
      addAddressTitle: 'ضيف عنوان جديد',
      labelHome: 'بيت',
      labelWork: 'شغل',
      labelOther: 'أخرى',
      addressLineLabel: 'العنوان بالتفصيل',
      addressLineHint: 'الشارع، رقم العمارة، الدور…',
      addAddressCta: 'حفظ العنوان',
      addressRequiredError: 'لازم تختار عنوان التوصيل الأول',
      addressSaveFailed: 'اتحفظ العنوان؟ لا — حاول تاني',
      subtotalRow: 'المجموع الفرعي',
      deliveryFeeRow: 'رسوم التوصيل',
      totalRow: 'الإجمالي',
      currencySuffix: 'ج.م',
      loyaltyBannerTemplate: 'هذا الطلب يضيف ~{points} نقطة لحسابك ☕',
      pointsBannerTemplate: 'هذا الطلب يضيف {points} نقطة لحسابك ☕',
      paymentCashHere: 'الدفع في الكافيه نقداً',
      paymentCashOnDelivery: 'الدفع عند الاستلام نقداً',
      confirmCta: 'تأكيد الطلب',
      submitFailed: 'فشل إرسال الطلب — حاول تاني',
      confirmedTitle: 'تم تأكيد طلبك!',
      etaPickup: '~10 دقائق',
      etaDelivery: '~30 دقيقة',
      itemsSummaryTitle: 'ملخص الطلب',
      trackCta: 'تتبع الطلب',
      trackingSoonStub: 'تتبع الحالة المباشر هيوصل قريب',
      backHomeCta: 'رجوع للرئيسية',
    ),
    AppLang.en: CheckoutStrings(
      cartTitle: 'Cart',
      emptyTitle: 'Your cart is empty',
      emptyBody: 'Pick something nice from the menu and start earning points',
      emptyCta: 'Browse menu',
      continueCta: 'Continue to payment',
      removeTooltip: 'Remove from cart',
      decreaseTooltip: 'Decrease quantity',
      increaseTooltip: 'Increase quantity',
      notesLabel: 'Order notes',
      notesHint: 'Any instructions for the whole order… e.g. no sugar anywhere',
      modeSelectionTitle: 'How do you want to order?',
      modeDineIn: 'Dine-in',
      modePickup: 'Pickup',
      modeDelivery: 'Delivery',
      modeDineInHelper: 'Check in, order from your table or the counter, earn points',
      modePickupHelper: 'Order now, pick up at Elkady Café',
      modeDeliveryHelper: 'Order to your address. Cash on delivery',
      checkoutTitle: 'Checkout',
      sectionDetails: 'Order details',
      tableFieldLabel: 'Table number',
      tableFieldHint: 'e.g. 12',
      areaInside: 'Inside',
      areaTerrace: 'Terrace',
      orSeparator: 'or',
      dineInMissingError: 'Pick a table number or an area',
      slotNow: 'Now',
      pickupMissingError: 'Choose a pickup time',
      savedAddressesLabel: 'Saved addresses',
      noAddressesLine: 'No saved address yet — add one',
      addAddressTitle: 'Add a new address',
      labelHome: 'Home',
      labelWork: 'Work',
      labelOther: 'Other',
      addressLineLabel: 'Full address',
      addressLineHint: 'Street, building number, floor…',
      addAddressCta: 'Save address',
      addressRequiredError: 'Pick a delivery address first',
      addressSaveFailed: "Couldn't save the address — try again",
      subtotalRow: 'Subtotal',
      deliveryFeeRow: 'Delivery fee',
      totalRow: 'Total',
      currencySuffix: 'EGP',
      loyaltyBannerTemplate: 'This order adds ~{points} pts to your account ☕',
      pointsBannerTemplate: 'This order adds {points} pts to your account ☕',
      paymentCashHere: 'Pay at the café in cash',
      paymentCashOnDelivery: 'Cash on delivery',
      confirmCta: 'Place order',
      submitFailed: "Couldn't place the order — try again",
      confirmedTitle: 'Your order is confirmed!',
      etaPickup: '~10 min',
      etaDelivery: '~30 min',
      itemsSummaryTitle: 'Order summary',
      trackCta: 'Track order',
      trackingSoonStub: 'Live tracking is coming soon',
      backHomeCta: 'Back to home',
    ),
  };

  static CheckoutStrings of(AppLang lang) => values[lang]!;
}
