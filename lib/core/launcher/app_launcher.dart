// App launcher wrapper — testable seam over url_launcher + Clipboard.
// Used by order status (customer→driver) and driver (driver→customer) comms
// to keep widget tests deterministic without hitting platform channels.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

abstract class AppLauncher {
  Future<bool> canLaunchUrl(Uri uri);
  Future<bool> launchUrl(Uri uri, {url_launcher.LaunchMode mode});
  Future<void> copy(String text);
}

class SystemAppLauncher implements AppLauncher {
  @override
  Future<bool> canLaunchUrl(Uri uri) async {
    try {
      return await url_launcher.canLaunchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> launchUrl(Uri uri, {url_launcher.LaunchMode mode = url_launcher.LaunchMode.externalApplication}) async {
    try {
      return await url_launcher.launchUrl(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}

final appLauncherProvider = Provider<AppLauncher>((ref) => SystemAppLauncher());

/// tel:+20 URI for Egyptian numbers — Western digits per §11.11.
Uri telUri(String phone) => Uri(scheme: 'tel', path: phone.trim());

/// Google Maps search URL — Arabic addresses percent-encoded via [Uri.encodeComponent].
Uri mapsUri(String address) =>
    Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address.trim())}');

String buildMapsUrl(String address) => mapsUri(address).toString();
