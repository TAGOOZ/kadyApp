// Strings catalog — ALL user-facing copy lives here (ar default, en toggle).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLang {
  ar('ar'),
  en('en');

  const AppLang(this.code);
  final String code;

  static const supportedLocales = [Locale('ar'), Locale('en')];
}

const sessionLocaleKey = 'session.locale';

class Strings {
  const Strings({
    required this.appName,
    required this.tagline,
    required this.welcomeHint,
    required this.demoButton,
    required this.tabHome,
    required this.tabMenu,
    required this.tabGames,
    required this.tabProfile,
    required this.roleCustomer,
    required this.roleStaff,
    required this.roleDriver,
    required this.roleAdmin,
    required this.roleSwitcherTitle,
    required this.roleSwitcherTile,
    required this.languageLabel,
    required this.langAr,
    required this.langEn,
    required this.ok,
    required this.homeLine,
    required this.menuLine,
    required this.gamesLine,
    required this.profileLine,
    required this.dashboardPrefix,
    required this.dashboardHint,
    required this.comingSoon,
  });

  final String appName;
  final String tagline;
  final String welcomeHint;
  final String demoButton;
  final String tabHome;
  final String tabMenu;
  final String tabGames;
  final String tabProfile;
  final String roleCustomer;
  final String roleStaff;
  final String roleDriver;
  final String roleAdmin;
  final String roleSwitcherTitle;
  final String roleSwitcherTile;
  final String languageLabel;
  final String langAr;
  final String langEn;
  final String ok;
  final String homeLine;
  final String menuLine;
  final String gamesLine;
  final String profileLine;
  final String dashboardPrefix;
  final String dashboardHint;
  final String comingSoon;

  String dashboardTitle(String roleName) => '$dashboardPrefix $roleName';
}

abstract final class AppStrings {
  static const Map<AppLang, Strings> values = {
    AppLang.ar: Strings(
      appName: 'كافيه القاضي',
      tagline: 'اكسب نقاط، العب ألعاب، واحصل على مكافآت',
      welcomeHint: 'اضغط مطولاً على الشعار لتبديل الدور أو اللغة',
      demoButton: 'دخول تجريبي',
      tabHome: 'الرئيسية',
      tabMenu: 'القائمة',
      tabGames: 'الألعاب',
      tabProfile: 'حسابي',
      roleCustomer: 'عميل',
      roleStaff: 'باريستا',
      roleDriver: 'سائق',
      roleAdmin: 'مدير',
      roleSwitcherTitle: 'تبديل الدور',
      roleSwitcherTile: 'تبديل الدور أو اللغة',
      languageLabel: 'اللغة',
      langAr: 'العربية',
      langEn: 'English',
      ok: 'حسناً',
      homeLine: 'الصفحة الرئيسية للعميل — النقاط والطوابع تظهر هنا لاحقاً',
      menuLine: 'قائمة الكافي — المشروبات والسناكس تُضاف في شريحة قادمة',
      gamesLine: 'مركز الألعاب — عجلة الحظ وبطاقات المطابقة قادمان',
      profileLine: 'حسابك وإعداداتك — الملف والعناوين المحفوظة لاحقاً',
      dashboardPrefix: 'لوحة',
      dashboardHint: 'شاشات العمليات تُبنى في شريحة قادمة',
      comingSoon: 'تسجيل الدخول عبر Google — قريباً',
    ),
    AppLang.en: Strings(
      appName: 'Elkady Café',
      tagline: 'Earn points, play games, get rewards',
      welcomeHint: 'Long-press the logo to switch role or language',
      demoButton: 'Try demo',
      tabHome: 'Home',
      tabMenu: 'Menu',
      tabGames: 'Games',
      tabProfile: 'Profile',
      roleCustomer: 'Customer',
      roleStaff: 'Barista',
      roleDriver: 'Driver',
      roleAdmin: 'Admin',
      roleSwitcherTitle: 'Switch role',
      roleSwitcherTile: 'Switch role or language',
      languageLabel: 'Language',
      langAr: 'العربية',
      langEn: 'English',
      ok: 'OK',
      homeLine: 'Customer home — points and stamps land here soon',
      menuLine: 'Café menu — drinks and snacks arrive in a coming slice',
      gamesLine: 'Games hub — spinner and match cards are coming',
      profileLine: 'Your account and settings — profile and saved addresses later',
      dashboardPrefix: 'Dashboard',
      dashboardHint: 'Operations screens are built in a coming slice',
      comingSoon: 'Sign in with Google — coming soon',
    ),
  };

  static Strings of(AppLang lang) => values[lang]!;

  // Numerals decision §11.11: Western 0123 in both Arabic and English.
  static String formatNumber(int value) => value.toString();
}

class LocaleNotifier extends Notifier<AppLang> {
  Completer<void>? _hydrating;

  @override
  AppLang build() {
    _ensureHydration();
    return AppLang.ar;
  }

  Future<void> get ready {
    _ensureHydration();
    return _hydrating!.future;
  }

  void _ensureHydration() {
    _hydrating ??= Completer<void>()..complete(_hydrate());
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(sessionLocaleKey);
    for (final lang in AppLang.values) {
      if (lang.code == code) {
        state = lang;
        return;
      }
    }
  }

  Future<void> setLang(AppLang lang) async {
    state = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sessionLocaleKey, lang.code);
  }
}

final localeNotifierProvider =
    NotifierProvider<LocaleNotifier, AppLang>(LocaleNotifier.new);
