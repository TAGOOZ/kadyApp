// TDD RED — Unsplash fallback URL mapping (issue #021).
// Pure helpers: no network, no widget — deterministic category → keyword → URL.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/core/images/unsplash.dart';
import 'package:kady_app/data/models/menu_models.dart';

void main() {
  group('unsplashUrlForCategory', () {
    const expectations = <String, String>{
      'turkish-coffee': 'https://source.unsplash.com/400x400/?turkish%20coffee,coffee,cafe',
      'espresso': 'https://source.unsplash.com/400x400/?espresso,coffee,cafe',
      'hot-drinks': 'https://source.unsplash.com/400x400/?hot%20coffee,coffee,cafe',
      'iced-espresso': 'https://source.unsplash.com/400x400/?iced%20coffee,coffee,cafe',
      'frappuccino': 'https://source.unsplash.com/400x400/?frappuccino,coffee,cafe',
      'desserts': 'https://source.unsplash.com/400x400/?dessert,coffee,cafe',
      'waffle': 'https://source.unsplash.com/400x400/?waffle,coffee,cafe',
      'fruit-salad': 'https://source.unsplash.com/400x400/?fruit%20salad,coffee,cafe',
      'ice-cream': 'https://source.unsplash.com/400x400/?ice%20cream,coffee,cafe',
      'bakery': 'https://source.unsplash.com/400x400/?bakery%20pastry,coffee,cafe',
      'extras': 'https://source.unsplash.com/400x400/?coffee,coffee,cafe',
      'winter-specials': 'https://source.unsplash.com/400x400/?hot%20chocolate,coffee,cafe',
    };

    for (final entry in expectations.entries) {
      test('${entry.key} → ${entry.value}', () {
        final url = unsplashUrlForCategory(entry.key);
        expect(url, entry.value);
        // Verify the URL contains the encoded keyword segment.
        final encodedKeyword = entry.value.split('?').last.split(',').first;
        expect(url, contains(encodedKeyword));
      });
    }

    test('unknown slug returns placeholder coffee URL', () {
      expect(
        unsplashUrlForCategory('unknown-slug'),
        'https://source.unsplash.com/400x400/?coffee,coffee,cafe',
      );
      expect(
        unsplashUrlForCategory(''),
        'https://source.unsplash.com/400x400/?coffee,coffee,cafe',
      );
    });

    test('is deterministic and pure', () {
      expect(
        unsplashUrlForCategory('espresso'),
        unsplashUrlForCategory('espresso'),
      );
    });
  });

  group('unsplashUrlForItem', () {
    const baseItem = MenuItem(
      id: '1',
      slug: 'latte',
      nameAr: 'لاتيه',
      nameEn: 'Latte',
      descAr: '',
      descEn: '',
      priceEgp: 45,
      isAvailable: true,
      categorySlug: 'espresso',
    );

    test('prefers imageUrl when non-null non-empty', () {
      const withImage = MenuItem(
        id: '1',
        slug: 'latte',
        nameAr: 'لاتيه',
        nameEn: 'Latte',
        descAr: '',
        descEn: '',
        priceEgp: 45,
        isAvailable: true,
        categorySlug: 'espresso',
        imageUrl: 'https://example.com/latte.jpg',
      );
      expect(unsplashUrlForItem(withImage), 'https://example.com/latte.jpg');
    });

    test('falls back to category when imageUrl is null', () {
      expect(
        unsplashUrlForItem(baseItem),
        'https://source.unsplash.com/400x400/?espresso,coffee,cafe',
      );
    });

    test('falls back when imageUrl is empty or whitespace', () {
      const emptyItem = MenuItem(
        id: '2',
        slug: 'espresso-double',
        nameAr: 'اسبريسو دبل',
        nameEn: 'Double Espresso',
        descAr: '',
        descEn: '',
        priceEgp: 60,
        isAvailable: true,
        categorySlug: 'turkish-coffee',
        imageUrl: '',
      );
      expect(
        unsplashUrlForItem(emptyItem),
        'https://source.unsplash.com/400x400/?turkish%20coffee,coffee,cafe',
      );
      const wsItem = MenuItem(
        id: '3',
        slug: 'ws',
        nameAr: 'ws',
        nameEn: 'ws',
        descAr: '',
        descEn: '',
        priceEgp: 10,
        isAvailable: true,
        categorySlug: 'bakery',
        imageUrl: '   ',
      );
      expect(
        unsplashUrlForItem(wsItem),
        'https://source.unsplash.com/400x400/?bakery%20pastry,coffee,cafe',
      );
    });

    test('unknown category with null imageUrl returns placeholder', () {
      const unknownCategory = MenuItem(
        id: '4',
        slug: 'mystery',
        nameAr: 'mystery',
        nameEn: 'mystery',
        descAr: '',
        descEn: '',
        priceEgp: 10,
        isAvailable: true,
        categorySlug: 'not-a-category',
      );
      expect(
        unsplashUrlForItem(unknownCategory),
        'https://source.unsplash.com/400x400/?coffee,coffee,cafe',
      );
    });

    test('covers all 12 seeded categories via item', () {
      const slugsAndKeywords = {
        'turkish-coffee': 'turkish%20coffee',
        'espresso': 'espresso',
        'hot-drinks': 'hot%20coffee',
        'iced-espresso': 'iced%20coffee',
        'frappuccino': 'frappuccino',
        'desserts': 'dessert',
        'waffle': 'waffle',
        'fruit-salad': 'fruit%20salad',
        'ice-cream': 'ice%20cream',
        'bakery': 'bakery%20pastry',
        'extras': 'coffee',
        'winter-specials': 'hot%20chocolate',
      };
      for (final e in slugsAndKeywords.entries) {
        final item = MenuItem(
          id: 'id-${e.key}',
          slug: 'slug-${e.key}',
          nameAr: 'ar',
          nameEn: 'en',
          descAr: '',
          descEn: '',
          priceEgp: 10,
          isAvailable: true,
          categorySlug: e.key,
        );
        final url = unsplashUrlForItem(item);
        expect(url, contains(e.value));
        expect(url, startsWith('https://source.unsplash.com/400x400/?'));
        expect(url, endsWith(',coffee,cafe'));
      }
    });
  });
}
