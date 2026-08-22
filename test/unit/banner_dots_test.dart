// Unit tests for the extracted banner-carousel math (issue #005).
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/ui/home/widgets/banner_carousel.dart';

void main() {
  group('nextBannerIndex', () {
    test('advances forward within the count', () {
      expect(nextBannerIndex(current: 0, count: 3), 1);
      expect(nextBannerIndex(current: 1, count: 3), 2);
    });

    test('wraps back to the first banner after the last', () {
      expect(nextBannerIndex(current: 2, count: 3), 0);
    });

    test('single banner stays put', () {
      expect(nextBannerIndex(current: 0, count: 1), 0);
    });

    test('degenerate counts degrade to the first index', () {
      expect(nextBannerIndex(current: 4, count: 0), 0);
      expect(nextBannerIndex(current: -1, count: -3), 0);
    });
  });
}
