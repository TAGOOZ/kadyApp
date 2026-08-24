// Maps config — central Cairo/Beni Suef fallback for Elkady Café.
// OpenStreetMap tiles via flutter_map; no API key needed (Phase 1).
// Cafe location approximated: Elkady Café, Beni Suef (29.066, 31.082).
import 'package:latlong2/latlong.dart';

/// Default cafe center — Beni Suef (Cairo fallback 30.0444,31.2357).
const elkadyCafeLatLng = LatLng(29.066, 31.082);
const elkadyCafeZoom = 13.0;

/// OSM tile template (no key, cacheable).
const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const osmTileSubdomains = <String>['a', 'b', 'c'];
