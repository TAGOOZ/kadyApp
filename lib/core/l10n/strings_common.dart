// Common strings catalog — exhaustive lint proof.
// Arabic-first RTL, Western digits §11.11. Buttons use verb+object;
// dismiss buttons say إغلاق never حسناً/OK (DESIGN Copy: Buttons: verb+object).
// Grep guard: no Text('…Arabic…') outside strings_*.dart.
import 'app_strings.dart';

class CommonStrings {
  const CommonStrings({
    required this.retry,
    required this.retryCta,
    required this.close,
    required this.okDeprecated,
    required this.loadFailed,
    required this.notFoundTitle,
    required this.notFoundBody,
    required this.backToHome,
    required this.qrScanTitle,
    required this.cameraUnavailable,
    required this.qrHint,
    required this.reassign,
    required this.open,
    required this.closed,
  });

  final String retry;
  final String retryCta;
  final String close;

  /// Deprecated: DESIGN bans حسناً, use [close] (إغلاق) for sheet dismiss.
  @Deprecated('Use close (إغلاق) per DESIGN Copy — حسناً is banned')
  final String okDeprecated;

  final String loadFailed;
  final String notFoundTitle;
  final String notFoundBody;
  final String backToHome;

  // QR scanner sheet (shared between home & staff)
  final String qrScanTitle;
  final String cameraUnavailable;
  final String qrHint;

  // Generic re-assign / open / closed toggles
  final String reassign;
  final String open;
  final String closed;

  static const CommonStrings _ar = CommonStrings(
    retry: 'إعادة المحاولة',
    retryCta: 'إعادة المحاولة',
    close: 'إغلاق',
    okDeprecated: 'حسناً',
    loadFailed: 'فشل التحميل — حاول مرة أخرى',
    notFoundTitle: 'غير موجود',
    notFoundBody: 'الصفحة غير موجودة',
    backToHome: 'العودة للرئيسية',
    qrScanTitle: 'مسح QR',
    cameraUnavailable: 'الكاميرا غير متاحة',
    qrHint: 'وجّه الكاميرا نحو رمز QR الخاص بالعميل',
    reassign: 'إعادة التعيين',
    open: 'افتح',
    closed: 'مغلق',
  );

  static const CommonStrings _en = CommonStrings(
    retry: 'Retry',
    retryCta: 'Retry',
    close: 'Close',
    okDeprecated: 'OK',
    loadFailed: 'Failed to load — try again',
    notFoundTitle: 'Not found',
    notFoundBody: 'Page not found',
    backToHome: 'Back to home',
    qrScanTitle: 'Scan QR',
    cameraUnavailable: 'Camera unavailable',
    qrHint: 'Point the camera at the customer QR code',
    reassign: 'Reassign',
    open: 'Open',
    closed: 'Closed',
  );

  static CommonStrings of(AppLang lang) => lang == AppLang.ar ? _ar : _en;
}
