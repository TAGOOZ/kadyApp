// Orders slice strings catalog (#006) — mirrors the AppStrings pattern
// (`app_strings.dart` is intentionally NOT edited; this file owns all
// user-facing copy for the orders list, status timeline and driver card).
// ar default, en toggle. Numerals: Western 0123 in both languages (§11.11).
import 'app_strings.dart';

class OrdersStrings {
  const OrdersStrings({
    required this.ordersTitle,
    required this.activeSection,
    required this.historySection,
    required this.emptyTitle,
    required this.emptyCta,
    required this.loadFailed,
    required this.retryCta,
    required this.itemsCountTemplate,
    required this.cancelledChip,
    required this.donePickupChip,
    required this.statusTitle,
    required this.orderNotFound,
    required this.driverLabel,
    required this.driverNamePlaceholder,
    required this.callSoonSnackbar,
    required this.mapHint,
    required this.directionsCta,
    required this.directionsSoonSnackbar,
    required this.cancelReasonLabel,
    required this.deliveredBannerTemplate,
    required this.trackOrderTooltip,
  });

  final String ordersTitle;

  /// `الطلبات النشطة` section header.
  final String activeSection;

  /// `السجل` section header (done/cancelled below active).
  final String historySection;
  final String emptyTitle;
  final String emptyCta;
  final String loadFailed;
  final String retryCta;

  /// `{items}` replaced with a Western-digit integer.
  final String itemsCountTemplate;

  /// Terminal chip for `cancelled` orders (list + timeline row).
  final String cancelledChip;

  /// Pickup orders reach `done` only after handoff — not a flow step,
  /// but the list still needs an Arabic chip for it.
  final String donePickupChip;
  final String statusTitle;
  final String orderNotFound;

  final String driverLabel;

  /// v1 placeholder name shown when a driver is assigned (#007 real data).
  final String driverNamePlaceholder;

  /// Phone row tap — `tel:` launch is out of scope for MVP.
  final String callSoonSnackbar;
  final String mapHint;
  final String directionsCta;
  final String directionsSoonSnackbar;
  final String cancelReasonLabel;

  /// `{label}` replaced with the mode's done-step Arabic label
  /// (تم التقديم / تم التوصيل).
  final String deliveredBannerTemplate;

  /// Confirmation-screen snackbar fallback when the order id can't be
  /// resolved from display number alone.
  final String trackOrderTooltip;

  String itemsCount(int count) =>
      itemsCountTemplate.replaceAll('{items}', '$count');

  String deliveredBanner(String doneLabelAr) =>
      deliveredBannerTemplate.replaceAll('{label}', doneLabelAr);

  /// `HH:mm` from a UTC instant rendered on the device clock — Western
  /// digits (§11.11).
  static String hhmmOf(DateTime utc) {
    final local = utc.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

abstract final class OrdersStringsCatalog {
  static const Map<AppLang, OrdersStrings> values = {
    AppLang.ar: OrdersStrings(
      ordersTitle: 'طلباتي',
      activeSection: 'الطلبات النشطة',
      historySection: 'السجل',
      emptyTitle: 'مفيش طلبات حالياً',
      emptyCta: 'اطلب دلوقتي',
      loadFailed: 'حصلت مشكلة في تحميل الطلبات',
      retryCta: 'إعادة المحاولة',
      itemsCountTemplate: '{items} أصناف',
      cancelledChip: 'مُلغي',
      donePickupChip: 'تم التسليم',
      statusTitle: 'تتبع الطلب',
      orderNotFound: 'مقدرناش نلاقي الطلب ده',
      driverLabel: 'السائق',
      driverNamePlaceholder: 'كريم م.',
      callSoonSnackbar: 'الاتصال قريبًا',
      mapHint: 'خريطة مباشرة قريبًا',
      directionsCta: 'فتح الاتجاهات',
      directionsSoonSnackbar: 'الاتجاهات المباشرة قريبًا',
      cancelReasonLabel: 'سبب الإلغاء',
      deliveredBannerTemplate: '{label} 🎉',
      trackOrderTooltip: 'لسه بنجهز تتبع الطلب — لحظات وجاي',
    ),
    AppLang.en: OrdersStrings(
      ordersTitle: 'My orders',
      activeSection: 'Active orders',
      historySection: 'History',
      emptyTitle: 'No orders yet',
      emptyCta: 'Order now',
      loadFailed: "Couldn't load your orders",
      retryCta: 'Retry',
      itemsCountTemplate: '{items} items',
      cancelledChip: 'Cancelled',
      donePickupChip: 'Picked up',
      statusTitle: 'Track order',
      orderNotFound: "We couldn't find that order",
      driverLabel: 'Driver',
      driverNamePlaceholder: 'Karim M.',
      callSoonSnackbar: 'Calling is coming soon',
      mapHint: 'Live map coming soon',
      directionsCta: 'Open directions',
      directionsSoonSnackbar: 'Live directions coming soon',
      cancelReasonLabel: 'Cancellation reason',
      deliveredBannerTemplate: '{label} 🎉',
      trackOrderTooltip: 'Tracking is being prepared — one moment',
    ),
  };

  static OrdersStrings of(AppLang lang) => values[lang]!;
}
