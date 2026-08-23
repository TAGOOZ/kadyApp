// Heritage Hearth design tokens — single source of truth for colors,
// radii, spacing, shadows and typography (docs/FEATURES.md §0).
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF003A2A);
  static const primaryContainer = Color(0xFF00533E);
  static const primaryFixedTint = Color(0xFFABF1D4);
  static const secondary = Color(0xFFA53C00);
  static const secondaryContainer = Color(0xFFFF7434);

  /// Muted ink for body/caption text on paper-white, parchment and
  /// background. [outline] keeps its role as a decorative stroke/divider
  /// color only — at #6F7974 it measures 4.30:1 on paper-white (below the
  /// 4.5:1 AA floor for body text), so it must not carry copy.
  static const textMuted = Color(0xFF55605B);
  static const parchment = Color(0xFFF9EBD7);
  static const paperWhite = Color(0xFFFFF9F0);
  static const coffeeBean = Color(0xFF4B2C20);
  static const background = Color(0xFFF8FAF6);
  static const error = Color(0xFFBA1A1A);
  static const outline = Color(0xFF6F7974);

  static const facebook = Color(0xFF1877F2);
  static const instagram = Color(0xFFE4405F);
  static const tiktok = Color(0xFF000000);
  static const whatsapp = Color(0xFF25D366);
}

abstract final class AppRadii {
  static const double sm4 = 4;
  static const double md8 = 8;
  static const double mdLg12 = 12;
  static const double lg16 = 16;
  static const double xl24 = 24;
  static const double pill = 9999;
}

abstract final class AppSpacing {
  static const double xs8 = 8;
  static const double sm16 = 16;
  static const double md24 = 24;
  static const double lg32 = 32;
  static const double xl48 = 48;
  static const double gutter16 = 16;
  static const double margin20 = 20;
}

abstract final class AppShadows {
  static const _coffeeShadowColor = Color(0x144B2C20);

  // "Coffee Shadows": soft, highly diffused warm tint (~8% coffee-bean).
  static List<BoxShadow> coffeeShadows({
    Offset offset = const Offset(0, 6),
    double blurRadius = 18,
  }) {
    return [
      BoxShadow(
        color: _coffeeShadowColor,
        offset: offset,
        blurRadius: blurRadius,
      ),
    ];
  }
}

/// Bundled families (pubspec `fonts:`): IBM Plex Sans is variable (wght),
/// Arabic ships as static weights. Latin glyphs resolve in IBM Plex Sans;
/// Arabic glyphs fall through to IBM Plex Sans Arabic.
abstract final class AppTextStyles {
  static const _fontFamily = 'IBM Plex Sans';
  static const _arabicFallback = ['IBM Plex Sans Arabic'];

  static TextStyle _style({
    double? fontSize,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: _fontFamily,
      fontFamilyFallback: _arabicFallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle get displayLg => _style(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.15,
      );

  static TextStyle get headlineLg =>
      _style(fontSize: 32, fontWeight: FontWeight.w600, height: 1.2);

  static TextStyle get headlineMobile =>
      _style(fontSize: 24, fontWeight: FontWeight.w600, height: 1.25);

  static TextStyle get titleMd =>
      _style(fontSize: 20, fontWeight: FontWeight.w600, height: 1.25);

  /// Card/list-item titles and in-card section headers (16px step between
  /// bodyLg and titleMd).
  static TextStyle get titleSm =>
      _style(fontSize: 16, fontWeight: FontWeight.w600, height: 1.25);

  static TextStyle get bodyLg =>
      _style(fontSize: 16, height: 1.35);

  static TextStyle get bodySm =>
      _style(fontSize: 14, height: 1.35);

  static TextStyle get labelMd =>
      _style(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.6, height: 1.3);

  /// Inline prices / money emphasis at list scale (menu rows, cart lines).
  static TextStyle get priceSm =>
      _style(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3);

  /// Large price display (item detail sheet).
  static TextStyle get priceLg =>
      _style(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25);
}

TextTheme _heritageHearthTextTheme() {
  return TextTheme(
    displayLarge: AppTextStyles.displayLg,
    displayMedium: AppTextStyles.headlineLg,
    displaySmall: AppTextStyles.headlineMobile,
    headlineLarge: AppTextStyles.headlineLg,
    headlineMedium: AppTextStyles.headlineMobile,
    headlineSmall: AppTextStyles.headlineMobile,
    titleLarge: AppTextStyles.titleMd,
    titleMedium: AppTextStyles.titleMd,
    titleSmall: AppTextStyles.titleMd,
    bodyLarge: AppTextStyles.bodyLg,
    bodyMedium: AppTextStyles.bodySm,
    bodySmall: AppTextStyles.bodySm,
    labelLarge: AppTextStyles.labelMd,
    labelMedium: AppTextStyles.labelMd,
    labelSmall: AppTextStyles.labelMd,
  );
}

ThemeData buildHeritageHearth(Brightness brightness) {
  const scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.parchment,
    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.secondaryContainer,
    onSecondaryContainer: AppColors.coffeeBean,
    error: AppColors.error,
    onError: Colors.white,
    surface: AppColors.paperWhite,
    onSurface: AppColors.coffeeBean,
    surfaceContainerHighest: AppColors.parchment,
    onSurfaceVariant: AppColors.coffeeBean,
    outline: AppColors.outline,
    surfaceTint: AppColors.parchment,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.parchment,
    textTheme: _heritageHearthTextTheme(),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.primaryContainer,
      foregroundColor: AppColors.paperWhite,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AppTextStyles.titleMd.copyWith(color: AppColors.paperWhite),
    ),
    cardTheme: CardThemeData(
      color: AppColors.paperWhite,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md8),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.primaryContainer,
      indicatorColor: AppColors.primaryFixedTint,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        AppTextStyles.labelMd.copyWith(color: AppColors.paperWhite),
      ),
      iconTheme: const WidgetStatePropertyAll(
        IconThemeData(color: AppColors.paperWhite),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: AppTextStyles.bodyLg.copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md24,
          vertical: AppSpacing.sm16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.parchment,
      labelStyle: AppTextStyles.labelMd,
      side: BorderSide(color: AppColors.outline.withValues(alpha: 0.25)),
      shape: const StadiumBorder(),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.outline.withValues(alpha: 0.25),
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: AppColors.primary),
  );
}
