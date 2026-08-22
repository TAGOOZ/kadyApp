import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/ui/games/match/match_screen.dart';

void main() {
  group('pick weights', () {
    test('distribution tracks 60/10/30 within tolerance over 500 seeded picks',
        () {
      const expected = {
        MatchOutcome.twoMatch: 60,
        MatchOutcome.threeMatch: 10,
        MatchOutcome.none: 30,
      };
      final counts = MatchRound.simulate(500, Random(11));
      counts.forEach((outcome, count) {
        final pct = count / 500 * 100;
        expect(pct, closeTo(expected[outcome]!.toDouble(), 6),
            reason: '$outcome off-weight');
      });
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      expect(total, 500);
    });
  });

  group('arrangeFaces', () {
    test('twoMatch yields exactly two equal symbols (never three)', () {
      final r = Random(5);
      for (var i = 0; i < 100; i++) {
        final faces = MatchRound.arrangeFaces(MatchOutcome.twoMatch, r);
        expect(faces.length, kMatchCardCount);
        // Three items over two distinct values ⇒ exactly one matching pair.
        expect(faces.toSet().length, 2,
            reason: 'exactly one pair expected in $faces');
      }
    });

    test('threeMatch yields all equal symbols', () {
      final r = Random(6);
      for (var i = 0; i < 100; i++) {
        final faces = MatchRound.arrangeFaces(MatchOutcome.threeMatch, r);
        expect(faces.toSet().length, 1, reason: '$faces must be uniform');
      }
    });

    test('none yields all-distinct symbols', () {
      final r = Random(9);
      for (var i = 0; i < 100; i++) {
        final faces = MatchRound.arrangeFaces(MatchOutcome.none, r);
        expect(faces.toSet().length, faces.length,
            reason: '$faces must be all-distinct');
      }
    });

    test('faces stay inside the symbol pool', () {
      final r = Random(13);
      for (final outcome in MatchOutcome.values) {
        for (var i = 0; i < 50; i++) {
          for (final f in MatchRound.arrangeFaces(outcome, r)) {
            expect(f, inInclusiveRange(0, kMatchFaces.length - 1));
          }
        }
      }
    });
  });
}
