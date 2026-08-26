// Risk verification queue strings catalog — RISK-06 (issue #51).
// Arabic-first RTL, Heritage Hearth tokens only, Western digits 0123 in both languages §11.11.
// No inline strings in widgets — all copy lives here keyed by AppLang{ar,en}.
import 'app_strings.dart';

class RiskStrings {
  const RiskStrings({
    required this.title,
    required this.queueTitle,
    required this.verificationRequired,
    required this.customerLabel,
    required this.phoneLabel,
    required this.orderLabel,
    required this.totalLabel,
    required this.riskScoreLabel,
    required this.riskLevelLabel,
    required this.actionLabel,
    required this.reasonsLabel,
    required this.confirmCta,
    required this.rejectCta,
    required this.riskLevelLow,
    required this.riskLevelMedium,
    required this.riskLevelHigh,
    required this.emptyQueue,
    required this.loadFailed,
    required this.retryCta,
    required this.lockTitle,
    required this.lockHint,
    required this.confirmSuccess,
    required this.rejectSuccess,
    required this.rejectTitle,
    required this.rejectHint,
    required this.rejectConfirm,
    required this.cancel,
    required this.failedSnack,
    required this.expandedProfileTitle,
    required this.expandedDeviceTitle,
    required this.expandedAddressTitle,
    required this.expandedEventsTitle,
    required this.addressOrdersTemplate,
    required this.addressSharedBadge,
    required this.deviceCountTemplate,
    required this.deviceSharedBadge,
    required this.riskEventsEmpty,
    required this.failedDeliveriesLabel,
    required this.cancelledLabel,
    required this.rejectedLabel,
    required this.riskScoreTemplate,
    required this.levelTemplate,
    required this.actionNeedsVerification,
    required this.actionApproved,
    required this.actionRejected,
  });

  final String title;
  final String queueTitle;
  final String verificationRequired;
  final String customerLabel;
  final String phoneLabel;
  final String orderLabel;
  final String totalLabel;
  final String riskScoreLabel;
  final String riskLevelLabel;
  final String actionLabel;
  final String reasonsLabel;
  final String confirmCta;
  final String rejectCta;
  final String riskLevelLow;
  final String riskLevelMedium;
  final String riskLevelHigh;
  final String emptyQueue;
  final String loadFailed;
  final String retryCta;
  final String lockTitle;
  final String lockHint;
  final String confirmSuccess;
  final String rejectSuccess;
  final String rejectTitle;
  final String rejectHint;
  final String rejectConfirm;
  final String cancel;
  final String failedSnack;
  final String expandedProfileTitle;
  final String expandedDeviceTitle;
  final String expandedAddressTitle;
  final String expandedEventsTitle;
  final String addressOrdersTemplate;
  final String addressSharedBadge;
  final String deviceCountTemplate;
  final String deviceSharedBadge;
  final String riskEventsEmpty;
  final String failedDeliveriesLabel;
  final String cancelledLabel;
  final String rejectedLabel;
  final String riskScoreTemplate;
  final String levelTemplate;
  final String actionNeedsVerification;
  final String actionApproved;
  final String actionRejected;

  String addressOrders(int count) => addressOrdersTemplate.replaceAll('{count}', '$count');
  String deviceCount(int count) => deviceCountTemplate.replaceAll('{count}', '$count');
  String riskScore(int score) => riskScoreTemplate.replaceAll('{score}', '$score');
  String level(String level) => levelTemplate.replaceAll('{level}', level);

  static const RiskStrings _ar = RiskStrings(
    title: 'التحقق',
    queueTitle: 'قائمة التحقق',
    verificationRequired: '⚠️ التحقق مطلوب',
    customerLabel: 'عميل',
    phoneLabel: 'الهاتف',
    orderLabel: 'طلب',
    totalLabel: 'الإجمالي',
    riskScoreLabel: 'درجة المخاطر',
    riskLevelLabel: 'المستوى',
    actionLabel: 'الإجراء',
    reasonsLabel: 'الأسباب',
    confirmCta: 'تأكيد',
    rejectCta: 'رفض',
    riskLevelLow: 'منخفض',
    riskLevelMedium: 'متوسط',
    riskLevelHigh: 'مرتفع',
    emptyQueue: 'لا توجد طلبات تحتاج تحقق',
    loadFailed: 'فشل تحميل قائمة التحقق',
    retryCta: 'إعادة المحاولة',
    lockTitle: 'قفل 🔒 بلا صلاحية',
    lockHint: 'شغّل SQL ترقية الحساب من docs/SUPABASE_SETUP.md',
    confirmSuccess: 'تم التأكيد ✅',
    rejectSuccess: 'تم الرفض',
    rejectTitle: 'سبب الرفض',
    rejectHint: 'اكتب سبب الرفض…',
    rejectConfirm: 'تأكيد الرفض',
    cancel: 'إلغاء',
    failedSnack: 'فشل — حاول مرة أخرى',
    expandedProfileTitle: 'سجل العميل',
    expandedDeviceTitle: 'أجهزة مرتبطة',
    expandedAddressTitle: 'العنوان',
    expandedEventsTitle: 'آخر الأحداث',
    addressOrdersTemplate: 'طلبات على العنوان: {count}',
    addressSharedBadge: 'عنوان مشترك',
    deviceCountTemplate: 'أجهزة مشتركة: {count}',
    deviceSharedBadge: 'جهاز مشترك',
    riskEventsEmpty: 'لا أحداث بعد',
    failedDeliveriesLabel: 'توصيلات فاشلة',
    cancelledLabel: 'ملغاة',
    rejectedLabel: 'مرفوضة',
    riskScoreTemplate: '{score}',
    levelTemplate: '{level}',
    actionNeedsVerification: 'needs_verification',
    actionApproved: 'approved',
    actionRejected: 'rejected',
  );

  static const RiskStrings _en = RiskStrings(
    title: 'Verification',
    queueTitle: 'Verification queue',
    verificationRequired: '⚠️ Verification Required',
    customerLabel: 'Customer',
    phoneLabel: 'Phone',
    orderLabel: 'Order',
    totalLabel: 'Total',
    riskScoreLabel: 'Risk Score',
    riskLevelLabel: 'Level',
    actionLabel: 'Action',
    reasonsLabel: 'Reasons',
    confirmCta: 'Confirm',
    rejectCta: 'Reject',
    riskLevelLow: 'Low',
    riskLevelMedium: 'Medium',
    riskLevelHigh: 'High',
    emptyQueue: 'No orders need verification',
    loadFailed: 'Failed to load verification queue',
    retryCta: 'Retry',
    lockTitle: 'Locked 🔒 no permission',
    lockHint: 'Run the account-elevation SQL from docs/SUPABASE_SETUP.md',
    confirmSuccess: 'Confirmed ✅',
    rejectSuccess: 'Rejected',
    rejectTitle: 'Rejection reason',
    rejectHint: 'Enter reason…',
    rejectConfirm: 'Confirm rejection',
    cancel: 'Cancel',
    failedSnack: 'Failed — Retry',
    expandedProfileTitle: 'Customer history',
    expandedDeviceTitle: 'Related devices',
    expandedAddressTitle: 'Address',
    expandedEventsTitle: 'Recent events',
    addressOrdersTemplate: 'Orders at address: {count}',
    addressSharedBadge: 'Shared address',
    deviceCountTemplate: 'Shared devices: {count}',
    deviceSharedBadge: 'Shared device',
    riskEventsEmpty: 'No events yet',
    failedDeliveriesLabel: 'Failed deliveries',
    cancelledLabel: 'Cancelled',
    rejectedLabel: 'Rejected',
    riskScoreTemplate: '{score}',
    levelTemplate: '{level}',
    actionNeedsVerification: 'needs_verification',
    actionApproved: 'approved',
    actionRejected: 'rejected',
  );

  static RiskStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;

  String levelLabel(String wire) => switch (wire) {
        'low' => riskLevelLow,
        'medium' => riskLevelMedium,
        'high' => riskLevelHigh,
        _ => wire,
      };
}

/// Humanised risk reason strings — mirrors plan §7 + OrdersStringsCatalog.
/// Used by verification cards: NEW_CUSTOMER → عميل جديد.
class RiskReasonStrings {
  const RiskReasonStrings({
    required this.newCustomer,
    required this.newDevice,
    required this.previousFailedDelivery,
    required this.previousRejectedOrder,
    required this.threePlusCancellations,
    required this.largeOrder,
    required this.rapidOrders,
    required this.threePlusSuccessful,
    required this.fivePlusSuccessful,
    required this.verifiedPhone,
    required this.multipleAccountsDevice,
    required this.multipleAccountsAddress,
    required this.addressHighFailure,
  });

  final String newCustomer;
  final String newDevice;
  final String previousFailedDelivery;
  final String previousRejectedOrder;
  final String threePlusCancellations;
  final String largeOrder;
  final String rapidOrders;
  final String threePlusSuccessful;
  final String fivePlusSuccessful;
  final String verifiedPhone;
  final String multipleAccountsDevice;
  final String multipleAccountsAddress;
  final String addressHighFailure;

  String humanize(String wire) => switch (wire) {
        'NEW_CUSTOMER' => newCustomer,
        'NEW_DEVICE' => newDevice,
        'PREVIOUS_FAILED_DELIVERY' => previousFailedDelivery,
        'PREVIOUS_REJECTED_ORDER' => previousRejectedOrder,
        'THREE_PLUS_CANCELLATIONS' => threePlusCancellations,
        'LARGE_ORDER' => largeOrder,
        'RAPID_ORDERS' => rapidOrders,
        'THREE_PLUS_SUCCESSFUL' => threePlusSuccessful,
        'FIVE_PLUS_SUCCESSFUL' => fivePlusSuccessful,
        'VERIFIED_PHONE' => verifiedPhone,
        'MULTIPLE_ACCOUNTS_DEVICE' => multipleAccountsDevice,
        'MULTIPLE_ACCOUNTS_ADDRESS' => multipleAccountsAddress,
        'ADDRESS_HIGH_FAILURE' => addressHighFailure,
        _ => '',
      };

  static const RiskReasonStrings _ar = RiskReasonStrings(
    newCustomer: 'عميل جديد',
    newDevice: 'جهاز جديد',
    previousFailedDelivery: 'توصيل سابق فشل',
    previousRejectedOrder: 'طلب سابق مرفوض',
    threePlusCancellations: '3+ إلغاءات',
    largeOrder: 'طلب كبير',
    rapidOrders: 'طلبات متتالية',
    threePlusSuccessful: '3+ طلبات ناجحة',
    fivePlusSuccessful: '5+ طلبات ناجحة',
    verifiedPhone: 'هاتف موثق',
    multipleAccountsDevice: 'جهاز مشترك',
    multipleAccountsAddress: 'عنوان مشترك',
    addressHighFailure: 'عنوان عالي الفشل',
  );

  static const RiskReasonStrings _en = RiskReasonStrings(
    newCustomer: 'New customer',
    newDevice: 'New device',
    previousFailedDelivery: 'Previous failed delivery',
    previousRejectedOrder: 'Previous rejected order',
    threePlusCancellations: '3+ cancellations',
    largeOrder: 'Large order',
    rapidOrders: 'Rapid orders',
    threePlusSuccessful: '3+ successful',
    fivePlusSuccessful: '5+ successful',
    verifiedPhone: 'Verified phone',
    multipleAccountsDevice: 'Shared device',
    multipleAccountsAddress: 'Shared address',
    addressHighFailure: 'High-failure address',
  );

  static RiskReasonStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
