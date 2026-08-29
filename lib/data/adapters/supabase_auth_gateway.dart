// Supabase implementation of AuthGateway — data-layer adapter.
// Domain owns the interface (lib/domain/auth_controller.dart); this file owns Supabase.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/supabase/supabase_config.dart';
import '../../domain/auth_controller.dart';

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
  Future<void> signOut() => _client()!.signOut(scope: sb.SignOutScope.global);
}
