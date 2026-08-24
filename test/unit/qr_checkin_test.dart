// TDD RED for P1-2 staff QR check-in parsing.
// Verifies parseQrPhone extracts and normalizes Egyptian phone from QR payloads.
// MUST fail before GREEN (no helper) and pass after.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/domain/qr_checkin.dart';

void main() {
  group('P1-2 QR phone parsing (RED)', () {
    test('parses bare +20 phone', () {
      expect(parseQrPhone('+201001234567'), '+201001234567');
      expect(parseQrPhone('  +201001234567  '), '+201001234567');
    });

    test('normalizes local 01 phone to +20', () {
      expect(parseQrPhone('01001234567'), '+201001234567');
      expect(parseQrPhone('01111234567'), '+201111234567');
    });

    test('parses kady:// URL with phone query param', () {
      expect(
        parseQrPhone('kady://checkin?phone=+201001234567'),
        '+201001234567',
      );
      expect(
        parseQrPhone('https://elkady.cafe/checkin?phone=01001234567&spend=60'),
        '+201001234567',
      );
    });

    test('parses JSON payload with phone field', () {
      expect(parseQrPhone('{"phone":"+201001234567"}'), '+201001234567');
      expect(parseQrPhone('{"phone":"01001234567","spend":80}'), '+201001234567');
    });

    test('returns null for invalid or missing phone', () {
      expect(parseQrPhone(''), isNull);
      expect(parseQrPhone('hello'), isNull);
      expect(parseQrPhone('kady://checkin?spend=60'), isNull);
      expect(parseQrPhone('{"spend":60}'), isNull);
      expect(parseQrPhone('+209999'), isNull);
    });

    test('domain/qr_checkin.dart file exists and contains parseQrPhone', () {
      final file = File('lib/domain/qr_checkin.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('parseQrPhone'));
      expect(content, contains('normalizeEgyptianPhone'));
    });

    test('checkin_sheet dart imports QR helper and has QR button', () {
      final content = File('lib/ui/staff/widgets/checkin_sheet.dart').readAsStringSync();
      expect(content, contains('qr_checkin'));
      expect(content, contains('parseQrPhone'));
      // Should have QR scan entry point (icon or button)
      expect(
        content,
        anyOf([
          contains('qr_code'),
          contains('MobileScanner'),
          contains('showQr'),
          contains('Qr'),
        ]),
      );
    });

    test('pubspec contains mobile_scanner dependency', () {
      final content = File('pubspec.yaml').readAsStringSync();
      expect(content, contains('mobile_scanner'));
    });
  });
}
