import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/core/l10n/app_strings.dart';
import 'package:kady_app/domain/session_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formatNumber renders Western digits', () {
    expect(AppStrings.formatNumber(1023), '1023');
    expect(AppStrings.formatNumber(0), '0');
  });

  test('LocaleNotifier defaults to ar and persists en switch', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final locale = container.read(localeNotifierProvider.notifier);
    await locale.ready;
    expect(container.read(localeNotifierProvider), AppLang.ar);

    await locale.setLang(AppLang.en);
    expect(container.read(localeNotifierProvider), AppLang.en);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(sessionLocaleKey), 'en');

    // Session mirrors the language once hydrated.
    await container.read(sessionControllerProvider.notifier).ready;
    expect(container.read(sessionControllerProvider).lang, AppLang.en);
  });
}
