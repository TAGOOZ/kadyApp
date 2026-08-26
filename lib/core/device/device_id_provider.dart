// Device ID provider — RISK-03
// Lightweight stable app-level device identifier per install (not browser
// fingerprinting). Stored once in SharedPreferences under `risk.device_id`
// as UUID v4, exposed via Riverpod for OrdersRepo.placeOrder.
// Value is untrusted server-side — treated as signal not proof.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// SharedPreferences key for the stable device identifier.
const String kDeviceIdPrefsKey = 'risk.device_id';

/// Generates or retrieves the stable device_id for this install.
///
/// - If [prefs] already contains `risk.device_id`, returns it.
/// - Otherwise generates UUID v4, persists it, and returns it.
/// Deterministic across restarts (stable) — tested via mock SharedPreferences.
Future<String> getOrCreateDeviceId(SharedPreferences prefs) async {
  final existing = prefs.getString(kDeviceIdPrefsKey);
  if (existing != null && existing.isNotEmpty) {
    return existing;
  }
  final uuid = Uuid();
  final newId = uuid.v4();
  await prefs.setString(kDeviceIdPrefsKey, newId);
  return newId;
}

/// Synchronous overrideable holder for the resolved device_id.
///
/// In production, override this via `deviceIdFutureProvider`'s resolved value
/// or via `ProviderScope` after initial load. Tests override directly with a
/// fake id without touching SharedPreferences.
final deviceIdProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'deviceIdProvider must be overridden with resolved device id — '
    'use deviceIdFutureProvider or override in ProviderScope',
  );
});

/// Async loader that reads/creates the device_id from SharedPreferences.
/// OrdersRepo and UI should `await ref.read(deviceIdFutureProvider.future)`
/// or watch this provider; for synchronous reads after load, override
/// `deviceIdProvider`.
final deviceIdFutureProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return getOrCreateDeviceId(prefs);
});

/// Helper to resolve device_id synchronously if already overridden, otherwise
/// falls back to loading from SharedPreferences. Used by OrdersRepo.placeOrder.
Future<String?> tryResolveDeviceId(Ref ref) async {
  String? sync;
  try {
    sync = ref.read(deviceIdProvider);
  } catch (_) {
    sync = null;
  }
  if (sync != null) return sync;
  try {
    return await ref.read(deviceIdFutureProvider.future);
  } catch (_) {
    return null;
  }
}
