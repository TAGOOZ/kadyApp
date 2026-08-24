// Menu item image — shows Storage photo when imageUrl exists, otherwise
// branded placeholder with product name (no Unsplash — source.unsplash 503
// causes CanvasKit texImage2D no image and unrelated generic images).
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
    this.label,
  });

  final double height;
  final double? width;
  final double iconSize;
  final double radius;
  final String? label;

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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('☕', style: TextStyle(fontSize: iconSize)),
          if (label != null && label!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.coffeeBean,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
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
    final rawUrl = item.imageUrl;
    final hasUrl = rawUrl != null && rawUrl.trim().isNotEmpty;
    if (!hasUrl) {
      // No photo yet — show branded placeholder with product name
      // instead of unrelated Unsplash generic (source.unsplash returns 503
      // and causes CanvasKit texImage2D no image). Product name is always
      // related; real photos will win via imageUrl when uploaded to
      // Storage bucket menu-photos (ADR-0005).
      return ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        child: MenuPhotoPlaceholder(
          height: height,
          width: width,
          radius: radius,
          iconSize: iconSize ?? (height >= 100 ? 36 : 28),
          label: height >= 100 ? item.nameAr : null,
        ),
      );
    }
    final resolvedUrl = rawUrl.trim();
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
          label: height >= 100 ? item.nameAr : null,
        ),
        errorWidget: (context, url, error) => MenuPhotoPlaceholder(
          height: height,
          width: width,
          radius: radius,
          iconSize: effectiveIconSize,
          label: height >= 100 ? item.nameAr : null,
        ),
      ),
    );
  }
}
