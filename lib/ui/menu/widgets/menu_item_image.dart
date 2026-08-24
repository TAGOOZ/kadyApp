// Menu item image with Unsplash fallback for missing photos.
// Uses cached_network_image with downscaling and MenuPhotoPlaceholder fallback.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/images/unsplash.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/menu_models.dart';

/// Branded photo placeholder — gradient + ☕ — shared by menu cards and
/// the detail sheet until photos are cached. Theme tokens only (no raw hex).
class MenuPhotoPlaceholder extends StatelessWidget {
  const MenuPhotoPlaceholder({
    super.key,
    this.height = 96,
    this.width,
    this.iconSize = 32,
    this.radius = AppRadii.mdLg12,
  });

  final double height;
  final double? width;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.parchment, AppColors.primaryFixedTint],
        ),
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
      alignment: Alignment.center,
      child: Text('☕', style: TextStyle(fontSize: iconSize)),
    );
  }
}

/// Renders the menu item photo via [CachedNetworkImage] with Unsplash
/// category fallback when [MenuItem.imageUrl] is null or empty.
/// Keeps downscaling via memCache hints and uses [MenuPhotoPlaceholder]
/// for both placeholder and error states.
class MenuItemImage extends StatelessWidget {
  const MenuItemImage({
    super.key,
    required this.item,
    this.width,
    required this.height,
    this.radius = AppRadii.mdLg12,
    this.iconSize,
  });

  final MenuItem item;
  final double? width;
  final double height;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = unsplashUrlForItem(item);
    // Downscale hints: use ~2x logical pixels when dimension is finite.
    final int? memCacheWidth = width != null && width!.isFinite
        ? (width! * 2).ceil()
        : null;
    final int? memCacheHeight = height.isFinite ? (height * 2).ceil() : null;
    final double effectiveIconSize = iconSize ?? (height >= 100 ? 56 : 30);

    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      child: CachedNetworkImage(
        imageUrl: resolvedUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: (context, url) => MenuPhotoPlaceholder(
          height: height,
          width: width,
          radius: radius,
          iconSize: effectiveIconSize,
        ),
        errorWidget: (context, url, error) => MenuPhotoPlaceholder(
          height: height,
          width: width,
          radius: radius,
          iconSize: effectiveIconSize,
        ),
      ),
    );
  }
}
