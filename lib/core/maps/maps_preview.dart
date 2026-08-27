// Reusable map preview — flutter_map + OSM, Cairo/Beni Suef center.
// Used by admin zones (polygon preview), driver live map, and customer
// order tracking. Handles empty/polygon/marker states with parchment fallback.
// Attribution: © OpenStreetMap via RichAttributionWidget (defect #1).
// Tile template uses {s} to match subdomains (defect #3).
// Lazy-loaded after first frame to avoid eager bundle jank (defect #6).
// Shows errorTileCallback/tileBuilder fallback (defect #7).
// Defaults to non-interactive with expand affordance to avoid ListView
// scroll jank (defect #10).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import 'maps_config.dart';

class MapsPreview extends StatefulWidget {
  const MapsPreview({
    super.key,
    this.center = elkadyCafeLatLng,
    this.zoom = elkadyCafeZoom,
    this.markers = const [],
    this.polygonPoints,
    this.polygons,
    this.height = 220,
    this.interactive = false,
  });

  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<LatLng>? polygonPoints;
  /// Multiple polygons — each entry is a separate zone (defect #4).
  /// Single-zone callers can keep using [polygonPoints]; master preview
  /// passes per-zone [Polygon] list here to avoid flattening disjoint zones.
  final List<Polygon>? polygons;
  final double height;
  final bool interactive;

  @override
  State<MapsPreview> createState() => _MapsPreviewState();

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

class _MapsPreviewState extends State<MapsPreview> {
  bool _ready = false;
  bool _interactiveOverride = false;

  @override
  void initState() {
    super.initState();
    // Lazy-load after first frame so parchment paints immediately (defect #6).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  void _showExpanded(BuildContext context) {
    final polygons = _buildPolygons();
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.sm16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.md8),
          child: SizedBox(
            height: 420,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: widget.center,
                    initialZoom: widget.zoom,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: osmTileUrl,
                      subdomains: osmTileSubdomains,
                      userAgentPackageName: 'com.elkadycafe.kady_app',
                      errorTileCallback: (tile, error, stack) {
                        debugPrint('OSM tile error: $error');
                      },
                      tileBuilder: (context, tileWidget, tile) {
                        if (tile.loadError) {
                          return Container(
                            color: AppColors.parchment,
                            alignment: Alignment.center,
                            child: const Icon(Icons.map_outlined, color: AppColors.textMuted, size: 20),
                          );
                        }
                        return tileWidget;
                      },
                    ),
                    if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
                    if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
                    if (widget.markers.isEmpty && polygons.isEmpty)
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
                    RichAttributionWidget(
                      alignment: AttributionAlignment.bottomRight,
                      popupBackgroundColor: AppColors.paperWhite,
                      showFlutterMapAttribution: false,
                      attributions: [
                        TextSourceAttribution(
                          'OpenStreetMap contributors',
                          prependCopyright: true,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: AppColors.paperWhite.withValues(alpha: 0.9),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.close_fullscreen, size: 20, color: AppColors.coffeeBean),
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Polygon> _buildPolygons() {
    if (widget.polygons != null && widget.polygons!.isNotEmpty) {
      return widget.polygons!;
    }
    if (widget.polygonPoints != null && widget.polygonPoints!.length >= 3) {
      return [
        Polygon(
          points: widget.polygonPoints!,
          color: AppColors.primaryContainer.withValues(alpha: 0.18),
          borderColor: AppColors.primary,
          borderStrokeWidth: 2,
        ),
      ];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final polygons = _buildPolygons();
    final effectiveInteractive = widget.interactive || _interactiveOverride;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md8),
      child: SizedBox(
        height: widget.height,
        child: _ready
            ? Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: widget.center,
                      initialZoom: widget.zoom,
                      interactionOptions: InteractionOptions(
                        flags: effectiveInteractive ? InteractiveFlag.all : InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: osmTileUrl,
                        subdomains: osmTileSubdomains,
                        userAgentPackageName: 'com.elkadycafe.kady_app',
                        errorTileCallback: (tile, error, stack) {
                          debugPrint('OSM tile error: $error');
                        },
                        tileBuilder: (context, tileWidget, tile) {
                          if (tile.loadError) {
                            return Container(
                              color: AppColors.parchment,
                              alignment: Alignment.center,
                              child: const Icon(Icons.map_outlined, color: AppColors.textMuted, size: 20),
                            );
                          }
                          return tileWidget;
                        },
                      ),
                      if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
                      if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
                      if (widget.markers.isEmpty && polygons.isEmpty)
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
                      RichAttributionWidget(
                        alignment: AttributionAlignment.bottomRight,
                        popupBackgroundColor: AppColors.paperWhite,
                        showFlutterMapAttribution: false,
                        attributions: [
                          TextSourceAttribution(
                            'OpenStreetMap contributors',
                            prependCopyright: true,
                            onTap: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Expand / interactivity affordance (defect #10).
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!effectiveInteractive)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Material(
                              color: AppColors.paperWhite.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppRadii.pill),
                                onTap: () => setState(() => _interactiveOverride = true),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.pan_tool_outlined, size: 14, color: AppColors.coffeeBean),
                                      const SizedBox(width: 4),
                                      Text(
                                        'تفعيل السحب',
                                        style: AppTextStyles.labelMd.copyWith(color: AppColors.coffeeBean, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Material(
                          color: AppColors.paperWhite.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(Icons.open_in_full, size: 18, color: AppColors.coffeeBean),
                            tooltip: 'تكبير الخريطة',
                            onPressed: () => _showExpanded(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Container(
                color: AppColors.parchment,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.map_outlined, color: AppColors.textMuted, size: 28),
                    const SizedBox(height: 6),
                    Text(
                      'خريطة — جار التحميل',
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
