// Reusable map preview — flutter_map + OSM, Cairo/Beni Suef center.
// Used by admin zones (polygon preview), driver live map, and customer
// order tracking. Handles empty/polygon/marker states with parchment fallback.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import 'maps_config.dart';

class MapsPreview extends StatelessWidget {
  const MapsPreview({
    super.key,
    this.center = elkadyCafeLatLng,
    this.zoom = elkadyCafeZoom,
    this.markers = const [],
    this.polygonPoints,
    this.height = 220,
    this.interactive = true,
  });

  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<LatLng>? polygonPoints;
  final double height;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md8),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            interactionOptions: InteractionOptions(
              flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: osmTileUrl,
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.elkadycafe.kady_app',
            ),
            if (polygonPoints != null && polygonPoints!.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: polygonPoints!,
                    color: AppColors.primaryContainer.withValues(alpha: 0.18),
                    borderColor: AppColors.primary,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            if (markers.isNotEmpty) MarkerLayer(markers: markers),
            // Cafe fixed marker when no custom markers.
            if (markers.isEmpty && (polygonPoints == null || polygonPoints!.isEmpty))
              MarkerLayer(
                markers: [
                  Marker(
                    point: elkadyCafeLatLng,
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.local_cafe, color: AppColors.primary, size: 28),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Helper: build a cafe + destination marker pair.
  static List<Marker> cafeToDestination(LatLng destination) => [
        Marker(
          point: elkadyCafeLatLng,
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: AppShadows.coffeeShadows(blurRadius: 6),
            ),
            child: const Icon(Icons.storefront_outlined, color: Colors.white, size: 20),
          ),
        ),
        Marker(
          point: destination,
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
              boxShadow: AppShadows.coffeeShadows(blurRadius: 6),
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 20),
          ),
        ),
      ];
}
