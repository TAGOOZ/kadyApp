// TDD RED — MenuItemImage fallback (issue #021).
// Verifies CachedNetworkImage uses Unsplash fallback when imageUrl is null/empty.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/core/images/unsplash.dart';
import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/ui/menu/widgets/menu_item_image.dart';

const _nullImageItem = MenuItem(
  id: '1',
  slug: 'latte',
  nameAr: 'لاتيه',
  nameEn: 'Latte',
  descAr: '',
  descEn: '',
  priceEgp: 45,
  isAvailable: true,
  categorySlug: 'espresso',
  imageUrl: null,
);

const _realImageItem = MenuItem(
  id: '2',
  slug: 'cheesecake',
  nameAr: 'تشيز كيك',
  nameEn: 'Cheesecake',
  descAr: '',
  descEn: '',
  priceEgp: 80,
  isAvailable: true,
  categorySlug: 'desserts',
  imageUrl: 'https://example.com/cheesecake.jpg',
);

const _emptyImageItem = MenuItem(
  id: '3',
  slug: 'empty',
  nameAr: 'فارغ',
  nameEn: 'Empty',
  descAr: '',
  descEn: '',
  priceEgp: 10,
  isAvailable: true,
  categorySlug: 'waffle',
  imageUrl: '',
);

void main() {
  testWidgets('null imageUrl renders CachedNetworkImage with unsplash fallback',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: _nullImageItem, width: 72, height: 72),
        ),
      ),
    );

    final finder = find.byType(CachedNetworkImage);
    expect(finder, findsOneWidget);
    final widget = tester.widget<CachedNetworkImage>(finder);
    expect(widget.imageUrl, unsplashUrlForCategory('espresso'));
    expect(widget.imageUrl, 'https://source.unsplash.com/400x400/?espresso,coffee,cafe');
  });

  testWidgets('real imageUrl renders CachedNetworkImage with that URL',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: _realImageItem, width: 72, height: 72),
        ),
      ),
    );

    final finder = find.byType(CachedNetworkImage);
    expect(finder, findsOneWidget);
    final widget = tester.widget<CachedNetworkImage>(finder);
    expect(widget.imageUrl, 'https://example.com/cheesecake.jpg');
    // Must not use fallback when imageUrl is present.
    expect(widget.imageUrl, isNot(contains('source.unsplash.com')));
  });

  testWidgets('empty imageUrl falls back to unsplash', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: _emptyImageItem, width: 72, height: 72),
        ),
      ),
    );

    final finder = find.byType(CachedNetworkImage);
    expect(finder, findsOneWidget);
    final widget = tester.widget<CachedNetworkImage>(finder);
    expect(widget.imageUrl, unsplashUrlForCategory('waffle'));
    expect(widget.imageUrl, 'https://source.unsplash.com/400x400/?waffle,coffee,cafe');
  });

  testWidgets('MenuItemImage clips with radius and keeps placeholder fallback',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(
            item: _nullImageItem,
            width: double.infinity,
            height: 180,
            radius: 16,
          ),
        ),
      ),
    );
    // Should be a ClipRRect with radius 16.
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(16));
    // CachedNetworkImage should have placeholder/errorWidget that resolves to MenuPhotoPlaceholder.
    // We verify placeholder builder exists by checking widget properties.
    final cached = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(cached.placeholder, isNotNull);
    expect(cached.errorWidget, isNotNull);
    // Also verify downscaling: memCache hints should be set for finite dimensions.
    // For width infinite, memCacheWidth should be null; height 180 -> memCacheHeight ~ 360.
    expect(cached.memCacheHeight, isNotNull);
  });

  testWidgets('winter-specials fallback uses hot chocolate keyword', (tester) async {
    const winterItem = MenuItem(
      id: 'w',
      slug: 'sahlab',
      nameAr: 'سحلب',
      nameEn: 'Sahlab',
      descAr: '',
      descEn: '',
      priceEgp: 70,
      isAvailable: true,
      categorySlug: 'winter-specials',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuItemImage(item: winterItem, width: 72, height: 72),
        ),
      ),
    );
    final widget = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(widget.imageUrl, 'https://source.unsplash.com/400x400/?hot%20chocolate,coffee,cafe');
  });
}
