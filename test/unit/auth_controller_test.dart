import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kady_app/data/repos/customers_repository.dart';
import 'package:kady_app/domain/auth_controller.dart';
import 'package:kady_app/domain/session_controller.dart';

class _FakeGateway implements AuthGateway {
  final _events = StreamController<GoogleProfile?>.broadcast();
  GoogleProfile? restored;
  Object? signInError;
  int signInCalls = 0;
  int signOutCalls = 0;

  @override
  Future<GoogleProfile?> restoreSession() async => restored;

  @override
  Stream<GoogleProfile?> get authStateChanges => _events.stream;

  @override
  Future<bool> signInWithGoogle(String redirectTo) async {
    signInCalls++;
    if (signInError != null) throw signInError!;
    return true;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _events.add(null);
  }

  void emit(GoogleProfile profile) => _events.add(profile);

  Future<void> dispose() async => _events.close();
}

class _FakeRepo implements CustomersRepo {
  final byGoogleId = <String, CustomerRecord>{};
  final takenPhones = <String>{};
  final upserts = <CustomerUpsert>[];

  @override
  Future<CustomerRecord?> findByGoogleUserId(String googleUserId) async =>
      byGoogleId[googleUserId];

  @override
  Future<CustomerRecord> upsert(CustomerUpsert customer) async {
    if (takenPhones.contains(customer.phone)) {
      throw const PhoneAlreadyLinkedException();
    }
    upserts.add(customer);
    final record = CustomerRecord(
      phone: customer.phone,
      name: customer.name,
      email: customer.email,
    );
    byGoogleId[customer.googleUserId] = record;
    return record;
  }
}

Future<void> _settle(AuthController notifier) async {
  await notifier.ready;
  await Future<void>.delayed(Duration.zero);
  await notifier.settled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGateway gateway;
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gateway = _FakeGateway();
    repo = _FakeRepo();
    container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        customersRepoProvider.overrideWithValue(repo),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await gateway.dispose();
  });

  test('google callback without a linked customer lands in authedWithoutPhone',
      () async {
    final notifier = container.read(authControllerProvider.notifier);
    await _settle(notifier);
    expect(container.read(authControllerProvider).phase, AuthPhase.idle);

    gateway.emit(const GoogleProfile(
      id: 'g-1',
      email: 'ahmed@gmail.com',
      name: 'Ahmed',
    ));
    await _settle(notifier);

    final state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.authedWithoutPhone);
    expect(state.googleUser?.email, 'ahmed@gmail.com');
    expect(state.googleUser?.name, 'Ahmed');
  });

  test('submitPhone with a free number reaches ready and exposes the phone',
      () async {
    final notifier = container.read(authControllerProvider.notifier);
    await _settle(notifier);
    gateway.emit(const GoogleProfile(id: 'g-1', email: 'a@b.com'));
    await _settle(notifier);

    final ok = await notifier.submitPhone(rawPhone: '01001234567', name: '');
    expect(ok, isTrue);

    final state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.ready);
    expect(state.phone, '+201001234567');
    expect(state.busy, isFalse);
    expect(state.error, AuthErrorCode.none);
    expect(repo.upserts.single.phone, '+201001234567');
    expect(repo.upserts.single.googleUserId, 'g-1');

    // Session hooks: onboarding done, guest flag cleared.
    final session = container.read(sessionControllerProvider);
    expect(session.onboarded, isTrue);
    expect(session.isGuest, isFalse);
  });

  test('duplicate phone maps to the duplicatePhone error state', () async {
    repo.takenPhones.add('+201001234567');
    final notifier = container.read(authControllerProvider.notifier);
    await _settle(notifier);
    gateway.emit(const GoogleProfile(id: 'g-2'));
    await _settle(notifier);

    final ok = await notifier.submitPhone(rawPhone: '+201001234567', name: 'X');
    expect(ok, isFalse);

    final state = container.read(authControllerProvider);
    expect(state.error, AuthErrorCode.duplicatePhone);
    expect(state.busy, isFalse);
    expect(state.phase, AuthPhase.authedWithoutPhone);
    expect(repo.upserts, isEmpty);
  });

  test('existing google customer resolves straight to ready', () async {
    repo.byGoogleId['g-3'] = const CustomerRecord(
      phone: '+201111111111',
      name: 'Sara',
    );
    gateway.restored = const GoogleProfile(id: 'g-3');
    final notifier = container.read(authControllerProvider.notifier);
    await _settle(notifier);

    final state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.ready);
    expect(state.phone, '+201111111111');
  });

  test('malformed phone input fails locally without touching the repo',
      () async {
    final notifier = container.read(authControllerProvider.notifier);
    await _settle(notifier);
    gateway.emit(const GoogleProfile(id: 'g-1'));
    await _settle(notifier);

    final ok = await notifier.submitPhone(rawPhone: '12345', name: 'X');
    expect(ok, isFalse);
    expect(container.read(authControllerProvider).error,
        AuthErrorCode.invalidPhone);
    expect(container.read(authControllerProvider).phase,
        AuthPhase.authedWithoutPhone);
    expect(repo.upserts, isEmpty);
  });

  test('signInWithGoogle failure degrades to googleUnavailable', () async {
    gateway.signInError = Exception('provider disabled');
    final notifier = container.read(authControllerProvider.notifier);
    await _settle(notifier);

    final ok = await notifier.signInWithGoogle();
    expect(ok, isFalse);
    final state = container.read(authControllerProvider);
    expect(state.error, AuthErrorCode.googleUnavailable);
    expect(state.phase, AuthPhase.idle);
  });

  test('continueAsGuest persists session.guest=true', () async {
    final notifier = container.read(authControllerProvider.notifier);
    await _settle(notifier);

    await notifier.continueAsGuest();

    final state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.guest);
    expect(container.read(sessionControllerProvider).isGuest, isTrue);
    expect(container.read(sessionControllerProvider).onboarded, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('session.guest'), isTrue);
  });

  test('signOut returns to idle and clears onboarding/guest flags', () async {
    final notifier = container.read(authControllerProvider.notifier);
    await _settle(notifier);
    await notifier.continueAsGuest();

    await notifier.signOut();

    final state = container.read(authControllerProvider);
    expect(state.phase, AuthPhase.idle);
    expect(gateway.signOutCalls, 1);
    expect(container.read(sessionControllerProvider).onboarded, isFalse);
    expect(container.read(sessionControllerProvider).isGuest, isFalse);
  });
}
