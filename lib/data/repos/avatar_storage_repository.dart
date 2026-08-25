import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';

abstract class AvatarStorageGateway {
  Future<void> uploadAvatar(String path, Uint8List bytes);
  String getPublicUrl(String path);
}

class SupabaseAvatarStorageGateway implements AvatarStorageGateway {
  const SupabaseAvatarStorageGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<void> uploadAvatar(String path, Uint8List bytes) async {
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
  }

  @override
  String getPublicUrl(String path) => _client.storage.from('avatars').getPublicUrl(path);
}

final avatarStorageGatewayProvider = Provider<AvatarStorageGateway>(
  (ref) => SupabaseAvatarStorageGateway(supabase),
);
