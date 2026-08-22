// Supabase bootstrap for kady_app.
// URL + publishable key are public (safe to bundle). Secret key stays server-only in .env.
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://zrlhtwmzuljsqricpxbb.supabase.co';
const supabaseAnonKey = 'sb_publishable_7eznl_xMNGXmxHSzWVdaJQ_r4dj3Apf';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    // ignore: deprecated_member_use — supabase_flutter 2.x still exposes anonKey; publishableKey alias lands in next major
  );
}

SupabaseClient get supabase => Supabase.instance.client;
