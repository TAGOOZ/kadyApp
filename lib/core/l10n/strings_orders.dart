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
    required this.verificationTitle,
    required this.verificationReasonsPrefix,
    required this.verificationBody,
    required this.rejectedBannerTemplate,
    required this.reasonNewCustomer,
    required this.reasonNewDevice,
    required this.reasonPreviousFailedDelivery,
    required this.reasonPreviousRejectedOrder,
    required this.reasonThreePlusCancellations,
    required this.reasonLargeOrder,
    required this.reasonRapidOrders,
    required this.reasonMultipleAccountsDevice,
    required this.reasonMultipleAccountsAddress,
    required this.reasonAddressHighFailure,
    required this.reasonVerifiedPhone,
    required this.reasonThreePlusSuccessful,
    required this.reasonFivePlusSuccessful,
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
  final String verificationTitle;
  final String verificationReasonsPrefix;
  final String verificationBody;
  final String rejectedBannerTemplate;
  final String reasonNewCustomer;
  final String reasonNewDevice;
  final String reasonPreviousFailedDelivery;
  final String reasonPreviousRejectedOrder;
  final String reasonThreePlusCancellations;
  final String reasonLargeOrder;
  final String reasonRapidOrders;
  final String reasonMultipleAccountsDevice;
  final String reasonMultipleAccountsAddress;
  final String reasonAddressHighFailure;
  final String reasonVerifiedPhone;
  final String reasonThreePlusSuccessful;
  final String reasonFivePlusSuccessful;

  String itemsCount(int count) =>
      itemsCountTemplate.replaceAll('{items}', '$count');

  String deliveredBanner(String doneLabelAr) =>
      deliveredBannerTemplate.replaceAll('{label}', doneLabelAr);

  String rejectedBanner(int score, String level) =>
      rejectedBannerTemplate.replaceAll('{score}', '$score').replaceAll('{level}', level);

  String humanizeReason(String wire) => switch (wire) {
        'NEW_CUSTOMER' => reasonNewCustomer,
        'NEW_DEVICE' => reasonNewDevice,
        'PREVIOUS_FAILED_DELIVERY' => reasonPreviousFailedDelivery,
        'PREVIOUS_REJECTED_ORDER' => reasonPreviousRejectedOrder,
        'THREE_PLUS_CANCELLATIONS' => reasonThreePlusCancellations,
        'LARGE_ORDER' => reasonLargeOrder,
        'RAPID_ORDERS' => reasonRapidOrders,
        'MULTIPLE_ACCOUNTS_DEVICE' => reasonMultipleAccountsDevice,
        'MULTIPLE_ACCOUNTS_ADDRESS' => reasonMultipleAccountsAddress,
        'ADDRESS_HIGH_FAILURE' => reasonAddressHighFailure,
        'VERIFIED_PHONE' => reasonVerifiedPhone,
        'THREE_PLUS_SUCCESSFUL' => reasonThreePlusSuccessful,
        'FIVE_PLUS_SUCCESSFUL' => reasonFivePlusSuccessful,
        // Unknown codes (e.g., RISK_EVALUATED summary event) are filtered — not shown to user
        _ => '',
      };

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
      verificationTitle: 'التحقق مطلوب — جارٍ مراجعة الطلب',
      verificationReasonsPrefix: 'الأسباب:',
      verificationBody: 'سيتم التأكيد قريباً — لا يمكن للطاقم قبول الطلب حتى اكتمال التحقق.',
      rejectedBannerTemplate: 'تم رفض الطلب تلقائياً — الدرجة {score} ({level})',
      reasonNewCustomer: 'عميل جديد',
      reasonNewDevice: 'جهاز جديد',
      reasonPreviousFailedDelivery: 'توصيل سابق فشل',
      reasonPreviousRejectedOrder: 'طلب سابق مرفوض',
      reasonThreePlusCancellations: '3+ إلغاءات',
      reasonLargeOrder: 'طلب كبير',
      reasonRapidOrders: 'طلبات متتالية',
      reasonMultipleAccountsDevice: 'جهاز مشترك',
      reasonMultipleAccountsAddress: 'عنوان مشترك',
      reasonAddressHighFailure: 'عنوان عالي الفشل',
      reasonVerifiedPhone: 'هاتف موثق',
      reasonThreePlusSuccessful: '3+ طلبات ناجحة',
      reasonFivePlusSuccessful: '5+ طلبات ناجحة',
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
      verificationTitle: 'Verification required — order under review',
      verificationReasonsPrefix: 'Reasons:',
      verificationBody: 'Will be confirmed shortly — staff cannot accept until verification completes.',
      rejectedBannerTemplate: 'Order automatically rejected — score {score} ({level})',
      reasonNewCustomer: 'New customer',
      reasonNewDevice: 'New device',
      reasonPreviousFailedDelivery: 'Previous failed delivery',
      reasonPreviousRejectedOrder: 'Previous rejected order',
      reasonThreePlusCancellations: '3+ cancellations',
      reasonLargeOrder: 'Large order',
      reasonRapidOrders: 'Rapid orders',
      reasonMultipleAccountsDevice: 'Shared device',
      reasonMultipleAccountsAddress: 'Shared address',
      reasonAddressHighFailure: 'High-failure address',
      reasonVerifiedPhone: 'Verified phone',
      reasonThreePlusSuccessful: '3+ successful',
      reasonFivePlusSuccessful: '5+ successful',
    ),
  };

  static OrdersStrings of(AppLang lang) => values[lang]!;
}
