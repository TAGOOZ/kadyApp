// Maps config — central Cairo/Beni Suef fallback for Elkady Café.
// OpenStreetMap tiles via flutter_map; no API key needed (Phase 1).
// Cafe location approximated: Elkady Café, Beni Suef (29.066, 31.082).
// NOTE: flutter_map & geolocator are eager imports; consider deferred
// `import ... deferred as` + `loadLibrary()` for smaller initial bundle.
// At minimum the map widget lazy-loads after first frame (see MapsPreview).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Default cafe center — Beni Suef (Cairo fallback 30.0444,31.2357).
const elkadyCafeLatLng = LatLng(29.066, 31.082);
const elkadyCafeZoom = 13.0;

/// OSM tile template (no key, cacheable).
/// Uses {s} subdomain placeholder to match [osmTileSubdomains].
const osmTileUrl = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const osmTileSubdomains = <String>['a', 'b', 'c'];

/// Test-mode guard for maps — override in ProviderScope for widget tests.
/// Replaces brittle string check (defect #5).
final mapsTestModeProvider = Provider<bool>((ref) => false);
