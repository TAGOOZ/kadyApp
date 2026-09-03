import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/domain/loyalty_rules.dart';
import 'package:kady_app/domain/loyalty_state.dart';

void main() {
  group('FIX #2 double cap', () {
    test('500 EGP pickup with double capped at +10', () {
      // base 50, doubled 100, extra 50 capped to 10 => 60
      expect(
        earnedFor(
          subtotalEgp: 500,
          dineIn: false,
          pointsPer10: 1,
          dineInMultiplier: 1.1,
          doubleWindow: true,
          doubleMaxExtra: 10,
        ),
        60,
      );
    });

    test('100 EGP dine-in with double capped', () {
      // base 11, doubled 22 extra 11 capped 10 =>21
      expect(
        earnedFor(
          subtotalEgp: 100,
          dineIn: true,
          pointsPer10: 1,
          dineInMultiplier: 1.1,
          doubleWindow: true,
          doubleMaxExtra: 10,
        ),
        21,
      );
    });

    test('small order double not capped', () {
      // 90 pickup dine-in 90*1.1=9.9=>10, doubled 19.8=>20 extra 10 not capped (extra=10)
      expect(
        earnedFor(
          subtotalEgp: 90,
          dineIn: true,
          pointsPer10: 1,
          dineInMultiplier: 1.1,
          doubleWindow: true,
          doubleMaxExtra: 10,
        ),
        20,
      );
      // 40 pickup base 4, doubled 8 extra 4 <10 =>8
      expect(
        earnedFor(
          subtotalEgp: 40,
          dineIn: false,
          pointsPer10: 1,
          dineInMultiplier: 1.1,
          doubleWindow: true,
          doubleMaxExtra: 10,
        ),
        8,
      );
    });

    test('custom cap respected', () {
      expect(
        earnedFor(
          subtotalEgp: 500,
          dineIn: false,
          pointsPer10: 1,
          dineInMultiplier: 1.1,
          doubleWindow: true,
          doubleMaxExtra: 15,
        ),
        65, // 50+15
      );
    });

    test('without double, cap ignored', () {
      expect(
        earnedFor(
          subtotalEgp: 500,
          dineIn: false,
          pointsPer10: 1,
          dineInMultiplier: 1.1,
          doubleWindow: false,
          doubleMaxExtra: 10,
        ),
        50,
      );
    });
  });

  group('FIX #8 token cap', () {
    test('grantStampsPure caps spinnerTokens at 5', () {
      // start at 4 tokens, next 3rd stamp would give +1 =>5
      var s = const LoyaltyState(stamps: 2, spinnerTokens: 4);
      s = grantStampsPure(s, 1); // 2->3 => token 5
      expect(s.spinnerTokens, 5);
      // next 3rd stamp (3->4 not multiple, 4->5 not, 5->6 multiple) would try to go to 6 but capped at 5
      s = grantStampsPure(s, 3); // 3->6
      expect(s.spinnerTokens, 5, reason: 'capped at 5, not 6');
    });

    test('already at cap 5, further 3rd stamps do not exceed', () {
      var s = const LoyaltyState(stamps: 0, spinnerTokens: 5);
      s = grantStampsPure(s, 9); // 0->9 would normally give 3 tokens (3,6,9) but capped
      expect(s.spinnerTokens, 5);
    });
  });

  group('LoyaltyRulesConfig parsing new keys', () {
    test('parses double_max_extra, spinner_token_cap, game_daily_limit', () {
      final c = LoyaltyRulesConfig.fromMap({
        'double_max_extra': 15,
        'spinner_token_cap': 7,
        'game_daily_limit': 5,
      });
      expect(c.doubleMaxExtra, 15);
      expect(c.spinnerTokenCap, 7);
      expect(c.gameDailyLimit, 5);
    });

    test('fallbacks when missing', () {
      final c = LoyaltyRulesConfig.fromMap({});
      expect(c.doubleMaxExtra, kDoubleMaxExtra);
      expect(c.spinnerTokenCap, kSpinnerTokenCap);
      expect(c.gameDailyLimit, kGameDailyLimit);
    });
  });
}
