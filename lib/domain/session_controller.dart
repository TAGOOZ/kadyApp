// Session state: language, role and onboarding gate, persisted locally.
// Language ownership lives in LocaleNotifier (`session.locale`);
// role + onboarding are owned here.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/app_strings.dart';

const _sessionRoleKey = 'session.role';
const _sessionOnboardedKey = 'session.onboarded';

enum AppRole { customer, staff, driver, admin }

class SessionState {
  const SessionState({
    this.lang = AppLang.ar,
    this.role = AppRole.customer,
    this.onboarded = false,
  });

  final AppLang lang;
  final AppRole role;
  final bool onboarded;

  SessionState copyWith({AppLang? lang, AppRole? role, bool? onboarded}) {
    return SessionState(
      lang: lang ?? this.lang,
      role: role ?? this.role,
      onboarded: onboarded ?? this.onboarded,
    );
  }
}

class SessionController extends Notifier<SessionState> {
  Completer<void>? _hydrating;

  @override
  SessionState build() {
    ref.listen(localeNotifierProvider, (_, lang) {
      state = state.copyWith(lang: lang);
    });
    _hydrating ??= Completer<void>()..complete(_hydrate());
    return SessionState(lang: ref.read(localeNotifierProvider));
  }

  Future<void> get ready => _hydrating!.future;

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final roleName = prefs.getString(_sessionRoleKey);
    for (final role in AppRole.values) {
      if (role.name == roleName) {
        state = state.copyWith(role: role);
        break;
      }
    }
    if (prefs.getBool(_sessionOnboardedKey) ?? false) {
      state = state.copyWith(onboarded: true);
    }
  }

  Future<void> setLang(AppLang lang) async {
    await ref.read(localeNotifierProvider.notifier).setLang(lang);
  }

  Future<void> setRole(AppRole role) async {
    state = state.copyWith(role: role);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionRoleKey, role.name);
  }

  Future<void> markOnboarded() async {
    state = state.copyWith(onboarded: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sessionOnboardedKey, true);
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

String roleNameOf(AppRole role, Strings strings) {
  return switch (role) {
    AppRole.customer => strings.roleCustomer,
    AppRole.staff => strings.roleStaff,
    AppRole.driver => strings.roleDriver,
    AppRole.admin => strings.roleAdmin,
  };
}
