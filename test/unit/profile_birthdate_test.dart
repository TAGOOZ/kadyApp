// Unit tests for the birthdate editor helper (#011): strict YYYY-MM-DD.
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/ui/profile/widgets/edit_field_sheet.dart';

void main() {
  group('parseBirthdateInput', () {
    test('accepts a valid past date', () {
      expect(parseBirthdateInput('2000-01-15'), DateTime(2000, 1, 15));
    });

    test('trims surrounding whitespace', () {
      expect(parseBirthdateInput(' 1999-12-31 '), DateTime(1999, 12, 31));
    });

    test('rejects empty and wrong formats', () {
      expect(parseBirthdateInput(''), isNull);
      expect(parseBirthdateInput('   '), isNull);
      expect(parseBirthdateInput('2000/01/15'), isNull);
      expect(parseBirthdateInput('15-01-2000'), isNull);
      expect(parseBirthdateInput('2000-1-5'), isNull);
      expect(parseBirthdateInput('abc-def-ghi'), isNull);
    });

    test('rejects calendar overflow dates', () {
      expect(parseBirthdateInput('2001-02-30'), isNull);
      expect(parseBirthdateInput('2000-13-01'), isNull);
      expect(parseBirthdateInput('2000-00-10'), isNull);
      expect(parseBirthdateInput('2000-04-00'), isNull);
    });

    test('rejects future dates', () {
      final tomorrow = DateTime.now().add(const Duration(days: 2));
      final stamp =
          '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      expect(parseBirthdateInput(stamp), isNull);
    });
  });
}
