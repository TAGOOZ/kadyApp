import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
import 'core/riverpod_retry.dart';
import 'core/l10n/kady_localizations.dart';
import 'core/router.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'domain/session_controller.dart';
import 'ui/widgets/bg_pattern.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(retry: noAutoRetry, child: KadyApp()));
}

class KadyApp extends ConsumerWidget {
  const KadyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    return MaterialApp.router(
      title: AppStrings.of(AppLang.en).appName,
      debugShowCheckedModeBanner: false,
      theme: buildHeritageHearth(Brightness.light),
      locale: Locale(session.lang.code),
      supportedLocales: AppLang.supportedLocales,
      localizationsDelegates: const [
        KadyMaterialLocalizationsDelegate(),
        KadyWidgetsLocalizationsDelegate(),
        KadyCupertinoLocalizationsDelegate(),
      ],
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => Container(
        color: AppColors.parchment,
        child: Stack(
          children: [
            const Positioned.fill(child: BgPattern()),
            // ignore: use_null_aware_elements
            if (child case final c?) c,
          ],
        ),
      ),
    );
  }
}
