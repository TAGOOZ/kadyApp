// Google OAuth gate + phone collection state machine.
// Domain-owned pure seam: AuthGateway interface lives here; Supabase
// implementation is in lib/data/adapters/supabase_auth_gateway.dart (DAG).
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'customer_gateway.dart';
import 'session_controller.dart';

const sessionGuestKey = 'session.guest';

enum AuthPhase { idle, authedWithoutPhone, ready, guest }

enum AuthErrorCode {
  none,
  googleUnavailable,
  invalidPhone,
  duplicatePhone,
  saveFailed,
}

class GoogleProfile {
  const GoogleProfile({required this.id, this.email = '', this.name = ''});

  final String id;
  final String email;
  final String name;
}

class AuthState {
  const AuthState({
    this.phase = AuthPhase.idle,
    this.googleUser,
    this.phone,
    this.busy = false,
    this.error = AuthErrorCode.none,
  });

  final AuthPhase phase;
  final GoogleProfile? googleUser;
  final String? phone;
  final bool busy;
  final AuthErrorCode error;

  AuthState copyWith({
    AuthPhase? phase,
    GoogleProfile? googleUser,
    String? phone,
    bool? busy,
    AuthErrorCode? error,
  }) {
    return AuthState(
      phase: phase ?? this.phase,
      googleUser: googleUser ?? this.googleUser,
      phone: phone ?? this.phone,
      busy: busy ?? this.busy,
      error: error ?? this.error,
    );
  }
}

bool isValidEgyptianPhone(String value) {
  return RegExp(r'^\+20[0-9]{10}$').hasMatch(value);
}

String normalizeEgyptianPhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.startsWith('+')) digits = digits.substring(1);
  if (digits.startsWith('20') && digits.length == 12) return '+$digits';
  if (digits.startsWith('0') && digits.length == 11) {
    return '+20${digits.substring(1)}';
  }
  if (digits.length == 10) return '+20$digits';
  return '+$digits';
}

/// Seam over supabase.auth so tests never touch the network.
abstract class AuthGateway {
  Future<GoogleProfile?> restoreSession();
  Stream<GoogleProfile?> get authStateChanges;
  Future<bool> signInWithGoogle(String redirectTo);
  Future<void> signOut();
}

/// Web goes through the CF Worker so we never use localhost as Site URL.
/// Set --dart-define=WORKER_CALLBACK_URL=https://kady-api.example.workers.dev/auth/callback?next=/
String oauthRedirectTarget() => kIsWeb
    ? const String.fromEnvironment(
        'WORKER_CALLBACK_URL',
        defaultValue:
            'https://kady-api.mostafatageldeen588.workers.dev/auth/callback?next=/',
      )
    : 'kadyapp://login-callback';

class _NoopAuthGateway implements AuthGateway {
  @override
  Stream<GoogleProfile?> get authStateChanges => const Stream.empty();
  @override
  Future<GoogleProfile?> restoreSession() async => null;
  @override
  Future<bool> signInWithGoogle(String redirectTo) async => false;
  @override
  Future<void> signOut() async {}
}

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => _NoopAuthGateway(),
);

class AuthController extends Notifier<AuthState> {
  Completer<void>? _hydrating;
  bool _hydrated = false;
  Future<void> _pendingAdoption = Future<void>.value();
  StreamSubscription<GoogleProfile?>? _subscription;

  /// Synchronous hydration flag for router guards.
  bool get isHydrated => _hydrated;

  @override
  AuthState build() {
    final gateway = ref.read(authGatewayProvider);
    _subscription?.cancel();
    _subscription = gateway.authStateChanges.listen((profile) {
      if (profile != null) {
        _pendingAdoption = _adopt(profile);
      } else {
        // External sign-out / session expired — clear authoritative role.
        _pendingAdoption = Future<void>.value();
        state = const AuthState(phase: AuthPhase.idle);
        // Fire-and-forget cache reset; ignore offline.
        // ignore: discarded_futures
        ref.read(sessionControllerProvider.notifier).clearServerRole();
      }
    });
    ref.onDispose(() => _subscription?.cancel());
    _hydrating ??= Completer<void>()..complete(_hydrate().whenComplete(() => _hydrated = true));
    return const AuthState(phase: AuthPhase.idle);
  }

  Future<void> get ready => (_hydrating ??= Completer<void>()
        ..complete(_hydrate().whenComplete(() => _hydrated = true)))
      .future;

  /// Completes once the latest OAuth-callback adoption has settled.
  Future<void> get settled => _pendingAdoption;

  Future<void> _hydrate() async {
    final restored = await ref.read(authGatewayProvider).restoreSession();
    if (restored != null) {
      await _adopt(restored);
      return;
    }
    await ref.read(sessionControllerProvider.notifier).ready;
    if (!ref.read(sessionControllerProvider).isGuest) return;
    if (state.phase == AuthPhase.idle && state.googleUser == null) {
      state = state.copyWith(phase: AuthPhase.guest);
    }
  }

  Future<void> _adopt(GoogleProfile profile) async {
    if ((state.phase == AuthPhase.ready ||
            state.phase == AuthPhase.authedWithoutPhone) &&
        state.googleUser?.id == profile.id) {
      // Re-sync role even on same profile — covers mid-session promotion.
      try {
        await ref.read(sessionControllerProvider.notifier).syncRoleFromServer(profile.id);
      } catch (_) {}
      return;
    }
    state = AuthState(phase: AuthPhase.idle, googleUser: profile);
    try {
      final existing =
          await ref.read(customersRepoProvider).findByGoogleUserId(profile.id);
      if (existing == null) {
        state = AuthState(
          phase: AuthPhase.authedWithoutPhone,
          googleUser: profile,
        );
        try {
          await ref.read(sessionControllerProvider.notifier).syncRoleFromServer(profile.id);
        } catch (_) {}
        return;
      }
      state = AuthState(
        phase: AuthPhase.ready,
        googleUser: profile,
        phone: existing.phone,
      );
      await ref.read(sessionControllerProvider.notifier).markPhoneLinked();
      try {
        await ref.read(sessionControllerProvider.notifier).syncRoleFromServer(profile.id);
      } catch (_) {}
    } on PhoneAlreadyLinkedException {
      state = state.copyWith(error: AuthErrorCode.duplicatePhone);
    } catch (_) {
      state = state.copyWith(error: AuthErrorCode.saveFailed);
    }
  }

  Future<bool> signInWithGoogle() async {
    try {
      final launched = await ref
          .read(authGatewayProvider)
          .signInWithGoogle(oauthRedirectTarget());
      if (!launched) throw StateError('oauth-not-launched');
      return true;
    } catch (_) {
      state = state.copyWith(error: AuthErrorCode.googleUnavailable);
      return false;
    }
  }

  Future<bool> submitPhone({
    required String rawPhone,
    required String name,
    String email = '',
    bool isStudent = false,
    DateTime? birthdate,
    String city = '',
  }) async {
    final phone = normalizeEgyptianPhone(rawPhone);
    if (!isValidEgyptianPhone(phone)) {
      state = state.copyWith(error: AuthErrorCode.invalidPhone);
      return false;
    }
    final google = state.googleUser ??
        GoogleProfile(id: '', email: email, name: '');
    state = state.copyWith(busy: true, error: AuthErrorCode.none);
    try {
      final record =
          await ref.read(customersRepoProvider).upsert(CustomerUpsert(
                phone: phone,
                googleUserId: google.id,
                name: name.trim().isNotEmpty
                    ? name.trim()
                    : (google.name.isNotEmpty ? google.name : 'عميل'),
                email: email.trim().isNotEmpty ? email.trim() : google.email,
                isStudent: isStudent,
                birthdate: birthdate,
                city: city.trim(),
              ));
      state = AuthState(
        phase: AuthPhase.ready,
        googleUser: google,
        phone: record.phone,
      );
      await ref.read(sessionControllerProvider.notifier).markOnboarded();
      await ref.read(sessionControllerProvider.notifier).setGuest(false);
      try {
        await ref.read(sessionControllerProvider.notifier).syncRoleFromServer(google.id);
      } catch (_) {}
      return true;
    } on PhoneAlreadyLinkedException {
      state = state.copyWith(busy: false, error: AuthErrorCode.duplicatePhone);
      return false;
    } catch (_) {
      state = state.copyWith(busy: false, error: AuthErrorCode.saveFailed);
      return false;
    }
  }

  Future<void> continueAsGuest() async {
    state = const AuthState(phase: AuthPhase.guest);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(sessionGuestKey, true);
    final session = ref.read(sessionControllerProvider.notifier);
    await session.setGuest(true);
    await session.markOnboarded();
  }

  Future<void> signOut() async {
    try {
      await ref.read(authGatewayProvider).signOut();
    } catch (_) {}
    state = const AuthState(phase: AuthPhase.idle);
    final session = ref.read(sessionControllerProvider.notifier);
    await session.resetToWelcome();
    try {
      await session.clearServerRole();
    } catch (_) {}
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
