// Minimal ar/en localizations so Directionality resolves RTL natively
// (flutter_localizations is outside the dependency budget).
// Only WidgetsLocalizations.textDirection drives app directionality;
// Material/Cupertino defaults stay English-only for now.
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class KadyMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const KadyMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    return SynchronousFuture<MaterialLocalizations>(
      const DefaultMaterialLocalizations(),
    );
  }

  @override
  bool shouldReload(KadyMaterialLocalizationsDelegate old) => false;
}

class KadyWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const KadyWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    return SynchronousFuture<WidgetsLocalizations>(
      locale.languageCode == 'ar'
          ? const _ArabicWidgetsLocalizations()
          : const DefaultWidgetsLocalizations(),
    );
  }

  @override
  bool shouldReload(KadyWidgetsLocalizationsDelegate old) => false;
}

class _ArabicWidgetsLocalizations extends DefaultWidgetsLocalizations {
  const _ArabicWidgetsLocalizations();

  @override
  TextDirection get textDirection => TextDirection.rtl;
}

class KadyCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const KadyCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    return SynchronousFuture<CupertinoLocalizations>(
      const DefaultCupertinoLocalizations(),
    );
  }

  @override
  bool shouldReload(KadyCupertinoLocalizationsDelegate old) => false;
}
