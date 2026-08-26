// Device ID provider tests — RISK-03
// Stable across restarts, mock SharedPreferences, UUID v4 format.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kady_app/core/device/device_id_provider.dart';

void main() {
  group('device_id_provider — stable per install', () {
    test('generates UUID v4 once and reuses on second call (same prefs)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = await getOrCreateDeviceId(prefs);
      expect(first, isNotEmpty);
      // UUID v4 pattern
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(first),
        isTrue,
        reason: 'should be UUID v4',
      );

      final second = await getOrCreateDeviceId(prefs);
      expect(second, first, reason: 'second call should return same persisted value');
      expect(prefs.getString(kDeviceIdPrefsKey), first);
    });

    test('stable across restarts — mock SharedPreferences with existing value', () async {
      SharedPreferences.setMockInitialValues({kDeviceIdPrefsKey: 'test-device-id-123'});
      final prefs = await SharedPreferences.getInstance();
      final id = await getOrCreateDeviceId(prefs);
      expect(id, 'test-device-id-123');
      // Second retrieval still same
      final prefs2 = await SharedPreferences.getInstance();
      final id2 = await getOrCreateDeviceId(prefs2);
      expect(id2, 'test-device-id-123');
    });

    test('persists to SharedPreferences under risk.device_id key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kDeviceIdPrefsKey), isNull);
      final id = await getOrCreateDeviceId(prefs);
      expect(prefs.getString(kDeviceIdPrefsKey), id);
    });

    test('deviceIdFutureProvider resolves via SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({kDeviceIdPrefsKey: 'future-id-abc'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final id = await container.read(deviceIdFutureProvider.future);
      expect(id, 'future-id-abc');
    });

    test('deviceIdFutureProvider generates new UUID when empty', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final id = await container.read(deviceIdFutureProvider.future);
      expect(id, isNotEmpty);
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(id),
        isTrue,
      );
      // Second read via same container should be same (FutureProvider caches)
      final id2 = await container.read(deviceIdFutureProvider.future);
      expect(id2, id);
    });

    test('deviceIdProvider override works (sync Provider<String>)', () async {
      const fakeId = 'overridden-device-id';
      final container = ProviderContainer(
        overrides: [deviceIdProvider.overrideWithValue(fakeId)],
      );
      addTearDown(container.dispose);
      expect(container.read(deviceIdProvider), fakeId);
    });

    test('deviceIdProvider throws when not overridden (requires FutureProvider)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(() => container.read(deviceIdProvider), throwsException);
    });

    test('getOrCreateDeviceId handles empty string as missing', () async {
      SharedPreferences.setMockInitialValues({kDeviceIdPrefsKey: ''});
      final prefs = await SharedPreferences.getInstance();
      final id = await getOrCreateDeviceId(prefs);
      expect(id, isNotEmpty);
      expect(id, isNot(''));
      expect(prefs.getString(kDeviceIdPrefsKey), isNot(''));
    });
  });
}
