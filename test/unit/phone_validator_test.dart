import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/domain/auth_controller.dart';

void main() {
  group('phone validator', () {
    test('accepts a valid Egyptian E.164 number', () {
      expect(isValidEgyptianPhone('+201001234567'), isTrue);
    });

    test('rejects a local number without the +20 prefix', () {
      expect(isValidEgyptianPhone('0101234567'), isFalse);
    });

    test('rejects a short number', () {
      expect(isValidEgyptianPhone('+20100123456'), isFalse);
    });

    test('rejects non-digit input', () {
      expect(isValidEgyptianPhone('+20abcdefghij'), isFalse);
      expect(isValidEgyptianPhone(''), isFalse);
    });
  });

  group('normalizeEgyptianPhone', () {
    test('keeps already-normalized numbers', () {
      expect(normalizeEgyptianPhone('+201001234567'), '+201001234567');
    });

    test('converts local 0-prefixed numbers', () {
      final normalized = normalizeEgyptianPhone('01001234567');
      expect(normalized, '+201001234567');
      expect(isValidEgyptianPhone(normalized), isTrue);
    });

    test('converts 10-digit input without prefix', () {
      expect(isValidEgyptianPhone(normalizeEgyptianPhone('1001234567')), isTrue);
    });

    test('lets malformed shapes fail validation downstream', () {
      expect(
        isValidEgyptianPhone(normalizeEgyptianPhone('12345')),
        isFalse,
      );
    });
  });
}
