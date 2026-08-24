// QR check-in helper — parses phone from QR payloads (FEATURES §11.31).
// Accepts bare phone, URL with ?phone=, or JSON {"phone": "..."}.
// Returns normalized +20XXXXXXXXXX or null when invalid.

import 'auth_controller.dart';

String? parseQrPhone(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // 1. JSON payload: {"phone": "..."}
  if (trimmed.startsWith('{')) {
    final match = RegExp(r'"phone"\s*:\s*"([^"]+)"').firstMatch(trimmed);
    if (match != null) {
      final candidate = match.group(1)!;
      final normalized = normalizeEgyptianPhone(candidate);
      if (isValidEgyptianPhone(normalized)) return normalized;
    }
    // If JSON but no valid phone, do not fallback to treating JSON as phone.
    // Continue to URL check then raw fallback will fail correctly.
  }

  // 2. URL with query param phone= (kady://checkin?phone=... or https://...)
  if (trimmed.contains('phone=')) {
    try {
      final uri = Uri.parse(trimmed);
      final phoneParam = uri.queryParameters['phone'];
      if (phoneParam != null && phoneParam.isNotEmpty) {
        final normalized = normalizeEgyptianPhone(phoneParam);
        if (isValidEgyptianPhone(normalized)) return normalized;
      }
    } catch (_) {
      // Ignore parse error, try regex fallback below.
    }
    // Regex fallback for custom schemes where Uri.parse may not populate query
    final phoneMatch = RegExp(r'phone=([^&\s"\\}]+)').firstMatch(trimmed);
    if (phoneMatch != null) {
      final decoded = Uri.decodeComponent(phoneMatch.group(1)!.trim());
      final normalized = normalizeEgyptianPhone(decoded);
      if (isValidEgyptianPhone(normalized)) return normalized;
    }
  }

  // 3. Bare phone string
  final normalized = normalizeEgyptianPhone(trimmed);
  if (isValidEgyptianPhone(normalized)) return normalized;
  return null;
}
