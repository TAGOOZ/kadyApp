// Staff board strings catalog (#012) — mirrors the OrdersStrings pattern
// (`app_strings.dart` is intentionally NOT edited; this file owns all
// user-facing copy for the orders board, transitions, reject sheet and
// check-in sheet). ar default, en toggle. Numerals: Western 0123 in both
// languages (§11.11).
import 'app_strings.dart';

class StaffStrings {
  const StaffStrings({
    required this.boardTitle,
    required this.avgPrepTemplate,
    required this.tabAll,
    required this.tabDineIn,
    required this.tabPickup,
    required this.tabDelivery,
    required this.statusNew,
    required this.statusAccepted,
    required this.statusInPrep,
    required this.statusReady,
    required this.statusOutForDelivery,
    required this.statusDone,
    required this.statusCancelled,
    required this.actionAccept,
    required this.actionReject,
    required this.actionStartPrep,
    required this.actionMarkReady,
    required this.actionHandover,
    required this.actionGiveToDriver,
    required this.actionDelivered,
    required this.rejectTitle,
    required this.rejectHint,
    required this.rejectConfirm,
    required this.timingNow,
    required this.pickupAtTemplate,
    required this.elapsedTemplate,
    required this.checkInTooltip,
    required this.checkInTitle,
    required this.fieldPhone,
    required this.phoneHint,
    required this.errorPhone,
    required this.fieldSpend,
    required this.errorSpend,
    required this.fieldArea,
    required this.areaInside,
    required this.areaTerrace,
    required this.fieldTable,
    required this.tableTemplate,
    required this.checkInSubmit,
    required this.checkInSaving,
    required this.visitOk,
    required this.visitPending,
    required this.newOrderTemplate,
    required this.emptyBoard,
    required this.loadFailed,
    required this.retryCta,
    required this.lockTitle,
    required this.lockHint,
    required this.errorGeneric,
    required this.transitionFailed,
    required this.assignDriverTitle,
    required this.assignDriverHint,
    required this.noDrivers,
    required this.confirmAssignment,
    required this.driverAssigned,
    required this.assignmentFailed,
    required this.etaSaved,
    required this.notesSaved,
    required this.etaSectionTitle,
    required this.etaSaveButton,
    required this.notesSectionTitle,
    required this.notesSaveButton,
    required this.notesHint,
    required this.qrScannerTitle,
    required this.cameraUnavailable,
    required this.qrHint,
  });

  final String boardTitle;

  /// `{min}` replaced with a Western-digit integer.
  final String avgPrepTemplate;
  final String tabAll;
  final String tabDineIn;
  final String tabPickup;
  final String tabDelivery;

  // Status chips — DB vocabulary (#0001_init.sql).
  final String statusNew;
  final String statusAccepted;
  final String statusInPrep;
  final String statusReady;
  final String statusOutForDelivery;
  final String statusDone;
  final String statusCancelled;

  // Action buttons per current status.
  final String actionAccept;
  final String actionReject;
  final String actionStartPrep;
  final String actionMarkReady;
  final String actionHandover;
  final String actionGiveToDriver;
  final String actionDelivered;

  final String rejectTitle;
  final String rejectHint;
  final String rejectConfirm;

  /// Pickup orders without an explicit slot (ASAP).
  final String timingNow;

  /// `{time}` replaced with Cairo `HH:mm` (ADR-0009).
  final String pickupAtTemplate;

  /// `{min}` replaced with whole minutes since creation.
  final String elapsedTemplate;

  final String checkInTooltip;
  final String checkInTitle;
  final String fieldPhone;
  final String phoneHint;

  /// Inline +20 regex validation message.
  final String errorPhone;
  final String fieldSpend;
  final String errorSpend;
  final String fieldArea;
  final String areaInside;
  final String areaTerrace;

  /// Optional table number appended to the area tag.
  final String fieldTable;

  /// `{table}` replaced with the entered number.
  final String tableTemplate;
  final String checkInSubmit;
  final String checkInSaving;

  /// Visit recorded AND stamp written (or not due).
  final String visitOk;

  /// Visit recorded but loyalty_state RLS blocked the direct stamp write —
  /// a server-side path lands post-MVP.
  final String visitPending;

  /// Realtime insert banner; `{num}` is the display number.
  final String newOrderTemplate;
  final String emptyBoard;
  final String loadFailed;
  final String retryCta;
  final String lockTitle;

  /// Pointer to the elevation SQL in docs/SUPABASE_SETUP.md (§Elevate).
  final String lockHint;
  final String errorGeneric;
  final String transitionFailed;
  final String assignDriverTitle;
  final String assignDriverHint;
  final String noDrivers;
  final String confirmAssignment;
  final String driverAssigned;
  final String assignmentFailed;
  final String etaSaved;
  final String notesSaved;
  final String etaSectionTitle;
  final String etaSaveButton;
  final String notesSectionTitle;
  final String notesSaveButton;
  final String notesHint;
  final String qrScannerTitle;
  final String cameraUnavailable;
  final String qrHint;

  static const StaffStrings _ar = StaffStrings(
    boardTitle: 'لوحة الطلبات',
    avgPrepTemplate: 'متوسط وقت التحضير {min} دقايق',
    tabAll: 'الكل',
    tabDineIn: 'صالة',
    tabPickup: 'استلام',
    tabDelivery: 'توصيل',
    statusNew: 'جديد',
    statusAccepted: 'مقبول',
    statusInPrep: 'قيد التحضير',
    statusReady: 'جاهز',
    statusOutForDelivery: 'خرج للتوصيل',
    statusDone: 'تم التسليم',
    statusCancelled: 'مُلغي',
    actionAccept: 'قبول',
    actionReject: 'رفض',
    actionStartPrep: 'ابدأ التحضير',
    actionMarkReady: 'جاهز',
    actionHandover: 'تم التسليم',
    actionGiveToDriver: 'تسليم للسائق',
    actionDelivered: 'تم التوصيل',
    rejectTitle: 'سبب الرفض',
    rejectHint: 'اكتب سبب رفض الطلب…',
    rejectConfirm: 'تأكيد الرفض',
    timingNow: 'الآن',
    pickupAtTemplate: 'استلام {time}',
    elapsedTemplate: '{min} د',
    checkInTooltip: 'تسجيل زيارة',
    checkInTitle: 'تسجيل زيارة داخل الكافيه',
    fieldPhone: 'رقم الموبايل',
    phoneHint: '+201001234567',
    errorPhone: 'الرقم لازم يبدأ بـ +20 ويكون 11 رقم',
    fieldSpend: 'المبلغ المنفق (جنيه)',
    errorSpend: 'اكتب مبلغ صحيح',
    fieldArea: 'المنطقة',
    areaInside: 'داخل',
    areaTerrace: 'تراس',
    fieldTable: 'رقم الطاولة (اختياري)',
    tableTemplate: 'طاولة {table}',
    checkInSubmit: 'تسجيل الزيارة',
    checkInSaving: 'جاري التسجيل…',
    visitOk: 'الزيارة اتسجلت ✅',
    visitPending: 'الزيارة اتسجلت — الختم يتضاف تلقائيًا قريبًا',
    newOrderTemplate: 'طلب جديد #{num} 🛎️',
    emptyBoard: 'مفيش طلبات حالياً',
    loadFailed: 'حصلت مشكلة في تحميل الطلبات',
    retryCta: 'إعادة المحاولة',
    lockTitle: 'قفل 🔒 بلا صلاحية موظف',
    lockHint: 'شغّل SQL ترقية الحساب من docs/SUPABASE_SETUP.md',
    errorGeneric: 'حصل خطأ، حاول تاني',
    transitionFailed: 'مقدرناش نحدّث حالة الطلب',
    assignDriverTitle: 'اختر السائق',
    assignDriverHint: 'اختار السائق اللي هيستلم الطلب',
    noDrivers: 'مفيش سائقين متاحين',
    confirmAssignment: 'تأكيد التسليم',
    driverAssigned: 'تم التسليم للسائق ✅',
    assignmentFailed: 'مقدرناش نسلم للسائق',
    etaSaved: 'تم تحديث الوقت المتوقع ✅',
    notesSaved: 'تم حفظ الملاحظات ✅',
    etaSectionTitle: 'الوقت المتوقع',
    etaSaveButton: 'حفظ الوقت',
    notesSectionTitle: 'ملاحظات التوصيل',
    notesSaveButton: 'حفظ الملاحظات',
    notesHint: 'مثال: برج 5، الدور الثالث...',
    qrScannerTitle: 'مسح QR',
    cameraUnavailable: 'الكاميرا غير متاحة',
    qrHint: 'وجّه الكاميرا نحو رمز QR الخاص بالعميل',
  );

  static const StaffStrings _en = StaffStrings(
    boardTitle: 'Orders board',
    avgPrepTemplate: 'Avg prep time {min} min',
    tabAll: 'All',
    tabDineIn: 'Dine-in',
    tabPickup: 'Pickup',
    tabDelivery: 'Delivery',
    statusNew: 'New',
    statusAccepted: 'Accepted',
    statusInPrep: 'In prep',
    statusReady: 'Ready',
    statusOutForDelivery: 'Out for delivery',
    statusDone: 'Completed',
    statusCancelled: 'Cancelled',
    actionAccept: 'Accept',
    actionReject: 'Reject',
    actionStartPrep: 'Start prep',
    actionMarkReady: 'Ready',
    actionHandover: 'Handed over',
    actionGiveToDriver: 'Hand to driver',
    actionDelivered: 'Delivered',
    rejectTitle: 'Rejection reason',
    rejectHint: 'Describe why this order is rejected…',
    rejectConfirm: 'Confirm rejection',
    timingNow: 'ASAP',
    pickupAtTemplate: 'Pickup {time}',
    elapsedTemplate: '{min}m',
    checkInTooltip: 'Record visit',
    checkInTitle: 'Walk-in visit check-in',
    fieldPhone: 'Phone number',
    phoneHint: '+201001234567',
    errorPhone: 'Number must look like +2010… (11 digits)',
    fieldSpend: 'Amount spent (EGP)',
    errorSpend: 'Enter a valid amount',
    fieldArea: 'Area',
    areaInside: 'Inside',
    areaTerrace: 'Terrace',
    fieldTable: 'Table number (optional)',
    tableTemplate: 'Table {table}',
    checkInSubmit: 'Record visit',
    checkInSaving: 'Recording…',
    visitOk: 'Visit recorded ✅',
    visitPending: 'Visit recorded — the stamp will be added automatically soon',
    newOrderTemplate: 'New order #{num} 🛎️',
    emptyBoard: 'No orders yet',
    loadFailed: "Couldn't load orders",
    retryCta: 'Retry',
    lockTitle: 'Locked 🔒 no staff permission',
    lockHint: 'Run the account-elevation SQL from docs/SUPABASE_SETUP.md',
    errorGeneric: 'Something went wrong, try again',
    transitionFailed: "Couldn't update the order status",
    assignDriverTitle: 'Pick a driver',
    assignDriverHint: 'Select the driver who will take this delivery',
    noDrivers: 'No drivers available',
    confirmAssignment: 'Confirm handover',
    driverAssigned: 'Handed to driver ✅',
    assignmentFailed: "Couldn't hand to driver",
    etaSaved: 'ETA updated ✅',
    notesSaved: 'Notes saved ✅',
    etaSectionTitle: 'Estimated time',
    etaSaveButton: 'Save time',
    notesSectionTitle: 'Delivery notes',
    notesSaveButton: 'Save notes',
    notesHint: 'e.g. Building 5, 3rd floor...',
    qrScannerTitle: 'Scan QR',
    cameraUnavailable: 'Camera unavailable',
    qrHint: 'Point the camera at the customer QR code',
  );

  static StaffStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;

  String avgPrep(int minutes) => avgPrepTemplate.replaceAll('{min}', '$minutes');

  String pickupAt(String hhmm) =>
      pickupAtTemplate.replaceAll('{time}', hhmm);

  String elapsed(int minutes) =>
      elapsedTemplate.replaceAll('{min}', '$minutes');

  String newOrder(int displayNumber) =>
      newOrderTemplate.replaceAll('{num}', '$displayNumber');

  String table(String number) => tableTemplate.replaceAll('{table}', number);
}
