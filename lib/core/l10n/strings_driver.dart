// Driver flow strings catalog (#014, FEATURES §7) — mirrors the StaffStrings
// pattern (`app_strings.dart` is intentionally NOT edited; this file owns
// every user-facing copy for the driver home tabs, order detail, stepper and
// history summary). ar default, en toggle. Numerals: Western 0123 in both
// languages (§11.11).
import 'app_strings.dart';

class DriverStrings {
  const DriverStrings({
    required this.homeTitle,
    required this.driverNameStub,
    required this.tabMyDeliveries,
    required this.tabHistory,
    required this.emptyAssigned,
    required this.emptyHistory,
    required this.pickupLine,
    required this.cashTemplate,
    required this.itemsCountTemplate,
    required this.newAssignment,
    required this.lockTitle,
    required this.lockHint,
    required this.loadFailed,
    required this.retryCta,
    required this.errorGeneric,
    required this.transitionFailed,
    required this.mapTitle,
    required this.openDirections,
    required this.linkCopied,
    required this.callComingSoon,
    required this.deliveryNotesLabel,
    required this.noNotes,
    required this.addressMissing,
    required this.stepAccepted,
    required this.stepPickedUp,
    required this.stepDelivered,
    required this.actionAccept,
    required this.actionPickedUp,
    required this.actionDelivered,
    required this.deliveredDone,
    required this.daySummaryTemplate,
    required this.orderItemsLabel,
  });

  final String homeTitle;

  /// Fixed identity until admin assignment exists (#014 stub).
  final String driverNameStub;
  final String tabMyDeliveries;
  final String tabHistory;

  /// طلباتي tab when the realtime feed is empty.
  final String emptyAssigned;
  final String emptyHistory;

  /// Card pickup line — always the single café branch.
  final String pickupLine;

  /// `{amount}` replaced with a Western-digit integer.
  final String cashTemplate;

  /// `{count}` replaced with the items jsonb line count.
  final String itemsCountTemplate;

  /// Realtime insert banner — توصيلة جديدة 🛵.
  final String newAssignment;
  final String lockTitle;

  /// Pointer to the elevation SQL in docs/SUPABASE_SETUP.md (§Elevate).
  final String lockHint;
  final String loadFailed;
  final String retryCta;
  final String errorGeneric;
  final String transitionFailed;

  /// Map placeholder card heading.
  final String mapTitle;
  final String openDirections;
  final String linkCopied;
  final String callComingSoon;
  final String deliveryNotesLabel;
  final String noNotes;

  /// Shown when the addresses lookup yields nothing for orders.address_id.
  final String addressMissing;

  // Horizontal stepper — تم القبول ← استلمت من الكافيه ← تم التوصيل.
  final String stepAccepted;
  final String stepPickedUp;
  final String stepDelivered;

  // Sticky bottom button labels per next step.
  final String actionAccept;
  final String actionPickedUp;
  final String actionDelivered;

  /// Button label once everything is done (disabled state).
  final String deliveredDone;

  /// `{n}` deliveries + `{total}` EGP collected today (Cairo day).
  final String daySummaryTemplate;
  final String orderItemsLabel;

  static const DriverStrings _ar = DriverStrings(
    homeTitle: 'توصيلات كافيه القاضي',
    driverNameStub: 'كريم م.',
    tabMyDeliveries: 'طلباتي',
    tabHistory: 'السجل',
    emptyAssigned: 'مفيش توصيلات حالياً',
    emptyHistory: 'مفيش توصيلات مكتملة لسه',
    pickupLine: 'الاستلام من كافيه القاضي ☕',
    cashTemplate: '{amount} ج.م كاش',
    itemsCountTemplate: '{count} أصناف',
    newAssignment: 'توصيلة جديدة 🛵',
    lockTitle: 'قفل 🔒 بلا صلاحية سائق',
    lockHint: 'شغّل SQL ترقية الحساب من docs/SUPABASE_SETUP.md',
    loadFailed: 'حصلت مشكلة في تحميل التوصيلات',
    retryCta: 'إعادة المحاولة',
    errorGeneric: 'حصل خطأ، حاول تاني',
    transitionFailed: 'مقدرناش نحدّث حالة التوصيلة',
    mapTitle: 'الموقع على الخريطة',
    openDirections: 'فتح الاتجاهات',
    linkCopied: 'تم نسخ الرابط',
    callComingSoon: 'الاتصال قريبًا',
    deliveryNotesLabel: 'ملاحظات التوصيل',
    noNotes: 'مفيش ملاحظات',
    addressMissing: 'العنوان غير متوفر',
    stepAccepted: 'تم القبول',
    stepPickedUp: 'استلمت من الكافيه',
    stepDelivered: 'تم التوصيل',
    actionAccept: 'قبول التوصيلة',
    actionPickedUp: 'استلمت من الكافيه',
    actionDelivered: 'تم التوصيل',
    deliveredDone: 'تم التوصيل ✅',
    daySummaryTemplate: 'توصيلات اليوم {n} · محصّل {total} ج.م',
    orderItemsLabel: 'محتويات الطلب',
  );

  static const DriverStrings _en = DriverStrings(
    homeTitle: 'Elkady Café deliveries',
    driverNameStub: 'Karim M.',
    tabMyDeliveries: 'My deliveries',
    tabHistory: 'History',
    emptyAssigned: 'No deliveries right now',
    emptyHistory: 'No completed deliveries yet',
    pickupLine: 'Pickup from Elkady Café ☕',
    cashTemplate: '{amount} EGP cash',
    itemsCountTemplate: '{count} items',
    newAssignment: 'New delivery 🛵',
    lockTitle: 'Locked 🔒 no driver permission',
    lockHint: 'Run the account-elevation SQL from docs/SUPABASE_SETUP.md',
    loadFailed: "Couldn't load deliveries",
    retryCta: 'Retry',
    errorGeneric: 'Something went wrong, try again',
    transitionFailed: "Couldn't update the delivery status",
    mapTitle: 'Location on the map',
    openDirections: 'Open directions',
    linkCopied: 'Link copied',
    callComingSoon: 'Calling coming soon',
    deliveryNotesLabel: 'Delivery notes',
    noNotes: 'No notes',
    addressMissing: 'Address unavailable',
    stepAccepted: 'Accepted',
    stepPickedUp: 'Picked up from café',
    stepDelivered: 'Delivered',
    actionAccept: 'Accept delivery',
    actionPickedUp: 'Picked up from café',
    actionDelivered: 'Delivered',
    deliveredDone: 'Delivered ✅',
    daySummaryTemplate: 'Today: {n} deliveries · Collected {total} EGP',
    orderItemsLabel: 'Order contents',
  );

  static DriverStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;

  String cash(int amount) => cashTemplate.replaceAll('{amount}', '$amount');

  String itemsCount(int count) =>
      itemsCountTemplate.replaceAll('{count}', '$count');

  String daySummary(int n, int totalEgp) => daySummaryTemplate
      .replaceAll('{n}', '$n')
      .replaceAll('{total}', '$totalEgp');
}
