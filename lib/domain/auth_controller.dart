// Google OAuth gate + phone collection state machine.
// Supabase Auth is the source of truth; phone stays the canonical Customer
// key (CONTEXT.md). All supabase calls sit behind seams so unit tests never
// hit the network.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../core/supabase/supabase_config.dart';
import '../data/repos/customers_repository.dart';
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

class SupabaseAuthGateway implements AuthGateway {
  sb.GoTrueClient? _client() {
    try {
      return supabase.auth;
    } catch (_) {
      return null;
    }
  }

  GoogleProfile _profileOf(sb.User user) {
    final meta = user.userMetadata;
    final name = meta == null ? null : (meta['full_name'] ?? meta['name']);
    return GoogleProfile(
      id: user.id,
      email: user.email ?? '',
      name: name is String ? name : '',
    );
  }

  @override
  Future<GoogleProfile?> restoreSession() async {
    final client = _client();
    final user = client?.currentUser;
    if (user == null) return null;
    return _profileOf(user);
  }

  @override
  Stream<GoogleProfile?> get authStateChanges {
    late final StreamController<GoogleProfile?> controller;
    StreamSubscription<sb.AuthState>? subscription;
    controller = StreamController<GoogleProfile?>.broadcast(
      onListen: () {
        final client = _client();
        if (client == null) return;
        subscription = client.onAuthStateChange.listen((event) {
          final user = event.session?.user;
          controller.add(user == null ? null : _profileOf(user));
        });
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<bool> signInWithGoogle(String redirectTo) {
    return _client()!.signInWithOAuth(
          sb.OAuthProvider.google,
          redirectTo: redirectTo,
        );
  }

  @override
  Future<void> signOut() => _client()!.signOut();
}

String oauthRedirectTarget() =>
    kIsWeb ? Uri.base.origin : 'kadyapp://login-callback';

final authGatewayProvider =
    Provider<AuthGateway>((ref) => SupabaseAuthGateway());

class AuthController extends Notifier<AuthState> {
  Completer<void>? _hydrating;
  Future<void> _pendingAdoption = Future<void>.value();
  StreamSubscription<GoogleProfile?>? _subscription;

  @override
  AuthState build() {
    final gateway = ref.read(authGatewayProvider);
    _subscription?.cancel();
    _subscription = gateway.authStateChanges.listen((profile) {
      if (profile != null) {
        _pendingAdoption = _adopt(profile);
      }
    });
    ref.onDispose(() => _subscription?.cancel());
    _hydrating ??= Completer<void>()..complete(_hydrate());
    return const AuthState(phase: AuthPhase.idle);
  }

  Future<void> get ready => (_hydrating ??= Completer<void>()
        ..complete(_hydrate()))
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
        return;
      }
      state = AuthState(
        phase: AuthPhase.ready,
        googleUser: profile,
        phone: existing.phone,
      );
      await ref.read(sessionControllerProvider.notifier).markPhoneLinked();
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
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);
