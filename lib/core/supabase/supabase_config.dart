// Supabase bootstrap for kady_app.
// URL + publishable key are public (safe to bundle). Secret key stays server-only in .env.
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://zrlhtwmzuljsqricpxbb.supabase.co';
const supabasePublishableKey = 'sb_publishable_7eznl_xMNGXmxHSzWVdaJQ_r4dj3Apf';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
}

SupabaseClient get supabase => Supabase.instance.client;
