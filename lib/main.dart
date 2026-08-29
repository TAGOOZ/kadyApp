import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_strings.dart';
import 'core/riverpod_retry.dart';
import 'core/l10n/kady_localizations.dart';
import 'core/router.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'data/adapters/supabase_auth_gateway.dart';
import 'data/adapters/supabase_driver_gateway.dart';
import 'data/adapters/supabase_loyalty_gateway.dart';
import 'data/adapters/supabase_phone_stamp_service.dart';
import 'data/repos/customers_repository.dart' show SupabaseCustomersRepo;
import 'data/repos/profile_repository.dart' show createSupabaseProfileGateway;
import 'domain/auth_controller.dart';
import 'domain/customer_gateway.dart';
import 'domain/driver_gateway.dart';
import 'domain/loyalty_gateway.dart';
import 'domain/phone_stamp_service.dart';
import 'domain/profile_gateway.dart';
import 'domain/session_controller.dart';
import 'ui/widgets/bg_pattern.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(
    ProviderScope(
      retry: noAutoRetry,
      overrides: [
        loyaltyGatewayProvider.overrideWithValue(SupabaseLoyaltyGateway(supabase)),
        authGatewayProvider.overrideWithValue(SupabaseAuthGateway()),
        customersRepoProvider.overrideWithValue(SupabaseCustomersRepo(supabase)),
        profileRoleGatewayProvider.overrideWithValue(createSupabaseProfileGateway()),
        driverProfileGatewayProvider.overrideWithValue(createSupabaseDriverGateway()),
        phoneStampServiceProvider.overrideWithValue(createSupabasePhoneStampService()),
        customerPhoneResolverProvider.overrideWithValue(createSupabasePhoneResolver()),
        customerLoyaltyOpsProvider.overrideWithValue(createSupabaseCustomerLoyaltyOps()),
      ],
      child: const KadyApp(),
    ),
  );
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
