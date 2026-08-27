// Strings catalog for the Admin dashboard (#015) — ar default, en toggle.
// Western digits everywhere (§11.11).
import 'app_strings.dart';

class AdminStrings {
  const AdminStrings({
    required this.title,
    required this.staffBoardChip,
    required this.tabCampaigns,
    required this.tabMenu,
    required this.tabRules,
    required this.tabReports,
    required this.tabDrivers,
    required this.tabHours,
    required this.tabZones,
    required this.assignDriver,
    required this.driverAssigned,
    required this.driverHint,
    required this.statusReady,
    required this.statusOutForDelivery,
    required this.kpiOrdersToday,
    required this.kpiActiveCustomers,
    required this.kpiAvgBasket,
    required this.currencySuffix,
    required this.kindDoublePoints,
    required this.kindMatchNight,
    required this.kindExamSeason,
    required this.kindRamadan,
    required this.doublePointsNote,
    required this.newCampaign,
    required this.campaignNameLabel,
    required this.campaignKindLabel,
    required this.startsAtLabel,
    required this.endsAtLabel,
    required this.pickDate,
    required this.save,
    required this.cancel,
    required this.delete,
    required this.edit,
    required this.undo,
    required this.addItem,
    required this.available,
    required this.unavailable,
    required this.deleteItemTitle,
    required this.deleteItemBodyFn,
    required this.saved,
    required this.revertedError,
    required this.lockTitle,
    required this.lockBody,
    required this.retry,
    required this.groupPoints,
    required this.groupStampsRedemption,
    required this.groupDelivery,
    required this.groupTiers,
    required this.groupProtectionLimits,
    required this.groupExtras,
    required this.ruleLabels,
    required this.modeDineIn,
    required this.modePickup,
    required this.modeDelivery,
    required this.topItemLabel,
    required this.noData,
    required this.fieldNameAr,
    required this.fieldNameEn,
    required this.fieldDescAr,
    required this.fieldDescEn,
    required this.fieldPrice,
    required this.fieldCategory,
    required this.fieldSort,
    required this.fieldImageUrl,
    required this.nameRequiredError,
    required this.priceInvalidError,
    required this.pricePositiveError,
    required this.sortInvalidError,
    required this.sortPositiveError,
    required this.imageUrlInvalidError,
    required this.campaignNameRequiredError,
    required this.endsBeforeStartError,
    required this.deleteCampaignTitle,
    required this.deleteCampaignBodyFn,
    required this.validationError,
  });

  final String title;
  final String staffBoardChip;
  final String tabCampaigns;
  final String tabMenu;
  final String tabRules;
  final String tabReports;
  final String tabDrivers;
  final String tabHours;
  final String tabZones;
  final String assignDriver;
  final String driverAssigned;
  final String driverHint;
  final String statusReady;
  final String statusOutForDelivery;
  final String kpiOrdersToday;
  final String kpiActiveCustomers;
  final String kpiAvgBasket;
  final String currencySuffix;
  final String kindDoublePoints;
  final String kindMatchNight;
  final String kindExamSeason;
  final String kindRamadan;
  final String doublePointsNote;
  final String newCampaign;
  final String campaignNameLabel;
  final String campaignKindLabel;
  final String startsAtLabel;
  final String endsAtLabel;
  final String pickDate;
  final String save;
  final String cancel;
  final String delete;
  final String edit;
  final String undo;
  final String addItem;
  final String available;
  final String unavailable;
  final String deleteItemTitle;
  final String Function(String name) deleteItemBodyFn;
  final String saved;
  final String revertedError;
  final String lockTitle;
  final String lockBody;
  final String retry;
  final String groupPoints;
  final String groupStampsRedemption;
  final String groupDelivery;
  final String groupTiers;
  final String groupProtectionLimits;
  final String groupExtras;

  /// app_config key → human label.
  final Map<String, String> ruleLabels;

  final String modeDineIn;
  final String modePickup;
  final String modeDelivery;
  final String topItemLabel;
  final String noData;
  final String fieldNameAr;
  final String fieldNameEn;
  final String fieldDescAr;
  final String fieldDescEn;
  final String fieldPrice;
  final String fieldCategory;
  final String fieldSort;
  final String fieldImageUrl;
  final String nameRequiredError;
  final String priceInvalidError;
  final String pricePositiveError;
  final String sortInvalidError;
  final String sortPositiveError;
  final String imageUrlInvalidError;
  final String campaignNameRequiredError;
  final String endsBeforeStartError;
  final String deleteCampaignTitle;
  final String Function(String name) deleteCampaignBodyFn;
  final String validationError;

  /// Arabic label for a campaign kind (wire vocabulary of `campaigns.kind`).
  String kindLabel(String kind) => switch (kind) {
        'double_points' => kindDoublePoints,
        'match_night' => kindMatchNight,
        'exam_season' => kindExamSeason,
        'ramadan' => kindRamadan,
        _ => kind,
      };

  static final AdminStrings _ar = AdminStrings(
    title: 'لوحة الإدارة',
    staffBoardChip: 'لوحة الطلبات',
    tabCampaigns: 'الحملات',
    tabMenu: 'القائمة',
    tabRules: 'القواعد',
    tabReports: 'التقارير',
    tabDrivers: 'التوصيل',
    tabHours: 'الساعات',
    tabZones: 'المناطق',
    assignDriver: 'تعيين السائق',
    driverAssigned: 'تم تعيين السائق ✅',
    driverHint: 'اختر سائقًا للتوصيل',
    statusReady: 'جاهز',
    statusOutForDelivery: 'خرج للتوصيل',
    kpiOrdersToday: 'طلبات اليوم',
    kpiActiveCustomers: 'عملاء نشطون',
    kpiAvgBasket: 'متوسط السلة ج.م',
    currencySuffix: 'ج.م',
    kindDoublePoints: 'نقاط مضاعفة',
    kindMatchNight: 'ليالي الماتشات',
    kindExamSeason: 'موسم الامتحانات',
    kindRamadan: 'رمضان',
    doublePointsNote: 'يُطبّق على الطلبات الجديدة فورًا',
    newCampaign: 'حملة جديدة',
    campaignNameLabel: 'اسم الحملة (عربي)',
    campaignKindLabel: 'النوع',
    startsAtLabel: 'تاريخ البداية',
    endsAtLabel: 'تاريخ النهاية',
    pickDate: 'اختر تاريخًا',
    save: 'حفظ',
    cancel: 'إلغاء',
    delete: 'حذف',
    edit: 'تعديل',
    undo: 'تراجع',
    addItem: 'صنف جديد',
    available: 'متاح',
    unavailable: 'غير متاح',
    deleteItemTitle: 'حذف الصنف؟',
    deleteItemBodyFn: (name) => 'سيتم إزالة «$name» من القائمة.',
    saved: 'تم الحفظ',
    revertedError: 'حدث خطأ — تم التراجع عن التغيير',
    lockTitle: 'بلا صلاحية مدير',
    lockBody: 'هذه اللوحة تحتاج صلاحية مدير على السيرفر. تواصل مع المالك لترقية حسابك.',
    retry: 'إعادة المحاولة',
    groupPoints: 'النقاط',
    groupStampsRedemption: 'الأختام والاستبدال',
    groupDelivery: 'التوصيل',
    groupTiers: 'التيرات',
    groupProtectionLimits: 'حدود الحماية',
    groupExtras: 'إضافي',
    ruleLabels: {
      'points_per_10egp': 'نقاط لكل 10 ج.م',
      'dine_in_multiplier': 'مضاعف الصالة',
      'stamp_min_spend': 'حد الأختام (ج.م)',
      'redeem_min_points': 'حد الاستبدال (نقطة)',
      'reward_topping': 'توبينج مجاني (نقطة)',
      'reward_snack': 'سناك مجاني (نقطة)',
      'reward_drink': 'مشروب مجاني (نقطة)',
      'delivery_fee': 'رسوم التوصيل (ج.م)',
      'tier_silver': 'التير الفضي (نقاط)',
      'tier_gold': 'التير الذهبي (نقاط)',
      'rate_limit_max': 'أقصى طلبات بالنافذة',
      'rate_limit_window_min': 'نافذة الحماية (دقيقة)',
      'double_window_active': 'نافذة مضاعفة نشطة',
      'group_checkin_count': 'عدد تسجيل المجموعة',
      'group_bonus_points': 'نقاط بونص المجموعة',
    },
    modeDineIn: 'صالة',
    modePickup: 'استلام',
    modeDelivery: 'توصيل',
    topItemLabel: 'أعلى صنف مبيعًا',
    noData: 'لا توجد بيانات بعد',
    fieldNameAr: 'الاسم (عربي)',
    fieldNameEn: 'Name (English)',
    fieldDescAr: 'الوصف (عربي)',
    fieldDescEn: 'Description (English)',
    fieldPrice: 'السعر (ج.م)',
    fieldCategory: 'التصنيف',
    fieldSort: 'الترتيب',
    fieldImageUrl: 'رابط الصورة',
    nameRequiredError: 'الاسم مطلوب',
    priceInvalidError: 'السعر غير صالح',
    pricePositiveError: 'السعر يجب أن يكون أكبر من صفر',
    sortInvalidError: 'الترتيب غير صالح',
    sortPositiveError: 'الترتيب لا يمكن أن يكون سالبًا',
    imageUrlInvalidError: 'رابط غير صالح (يجب أن يبدأ بـ https://)',
    campaignNameRequiredError: 'اسم الحملة مطلوب',
    endsBeforeStartError: 'تاريخ النهاية يجب أن يكون بعد البداية',
    deleteCampaignTitle: 'حذف الحملة؟',
    deleteCampaignBodyFn: (name) => 'سيتم حذف «$name» نهائيًا.',
    validationError: 'يرجى تصحيح الحقول المميزة',
  );

  static final AdminStrings _en = AdminStrings(
    title: 'Admin',
    staffBoardChip: 'Orders board',
    tabCampaigns: 'Campaigns',
    tabMenu: 'Menu',
    tabRules: 'Rules',
    tabReports: 'Reports',
    tabDrivers: 'Drivers',
    tabHours: 'Hours',
    tabZones: 'Zones',
    assignDriver: 'Assign driver',
    driverAssigned: 'Driver assigned ✅',
    driverHint: 'Pick a driver for this delivery',
    statusReady: 'Ready',
    statusOutForDelivery: 'Out for delivery',
    kpiOrdersToday: "Today's orders",
    kpiActiveCustomers: 'Active customers',
    kpiAvgBasket: 'Avg basket EGP',
    currencySuffix: 'EGP',
    kindDoublePoints: 'Double points',
    kindMatchNight: 'Match nights',
    kindExamSeason: 'Exam season',
    kindRamadan: 'Ramadan',
    doublePointsNote: 'Applies to new orders immediately',
    newCampaign: 'New campaign',
    campaignNameLabel: 'Campaign name (Arabic)',
    campaignKindLabel: 'Kind',
    startsAtLabel: 'Start date',
    endsAtLabel: 'End date',
    pickDate: 'Pick a date',
    save: 'Save',
    cancel: 'Cancel',
    delete: 'Delete',
    edit: 'Edit',
    undo: 'Undo',
    addItem: 'New item',
    available: 'Available',
    unavailable: 'Unavailable',
    deleteItemTitle: 'Delete item?',
    deleteItemBodyFn: (name) => '"$name" will be removed from the menu.',
    saved: 'Saved',
    revertedError: 'Something went wrong — change reverted',
    lockTitle: 'No admin access',
    lockBody:
        'This dashboard requires the admin role on the server. Ask the owner to elevate your account.',
    retry: 'Retry',
    groupPoints: 'Points',
    groupStampsRedemption: 'Stamps & redemption',
    groupDelivery: 'Delivery',
    groupTiers: 'Tiers',
    groupProtectionLimits: 'Protection limits',
    groupExtras: 'Extras',
    ruleLabels: {
      'points_per_10egp': 'Points per 10 EGP',
      'dine_in_multiplier': 'Dine-in multiplier',
      'stamp_min_spend': 'Stamp threshold (EGP)',
      'redeem_min_points': 'Redemption floor (pts)',
      'reward_topping': 'Free topping (pts)',
      'reward_snack': 'Free snack (pts)',
      'reward_drink': 'Free drink (pts)',
      'delivery_fee': 'Delivery fee (EGP)',
      'tier_silver': 'Silver tier (pts)',
      'tier_gold': 'Gold tier (pts)',
      'rate_limit_max': 'Max requests per window',
      'rate_limit_window_min': 'Rate-limit window (min)',
      'double_window_active': 'Double window active',
      'group_checkin_count': 'Group check-in count',
      'group_bonus_points': 'Group bonus points',
    },
    modeDineIn: 'Dine-in',
    modePickup: 'Pickup',
    modeDelivery: 'Delivery',
    topItemLabel: 'Top seller',
    noData: 'No data yet',
    fieldNameAr: 'الاسم (عربي)',
    fieldNameEn: 'Name (English)',
    fieldDescAr: 'الوصف (عربي)',
    fieldDescEn: 'Description (English)',
    fieldPrice: 'Price (EGP)',
    fieldCategory: 'Category',
    fieldSort: 'Sort order',
    fieldImageUrl: 'Image URL',
    nameRequiredError: 'Name is required',
    priceInvalidError: 'Price is invalid',
    pricePositiveError: 'Price must be > 0',
    sortInvalidError: 'Sort is invalid',
    sortPositiveError: 'Sort cannot be negative',
    imageUrlInvalidError: 'Invalid URL (must start with https://)',
    campaignNameRequiredError: 'Campaign name is required',
    endsBeforeStartError: 'End date must be after start date',
    deleteCampaignTitle: 'Delete campaign?',
    deleteCampaignBodyFn: (name) => '"$name" will be permanently deleted.',
    validationError: 'Please fix the highlighted fields',
  );

  static AdminStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
