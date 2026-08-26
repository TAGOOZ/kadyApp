// RISK-05 verification abstraction tests — provider-agnostic manual provider.
// No network, no Supabase — pure Dart via FakeVerificationRepo.
// Covers AC: request creates pending, verify with manual always false until staff confirms,
// expired request cannot be confirmed, double-confirm idempotent, plaintext code never stored (code_hash != code).

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/verification_repository.dart';
import 'package:kady_app/domain/verification_service.dart';

void main() {
  group('VerificationService — request creates pending (manual provider)', () {
    test('request creates pending with manual provider and expiry 15m', () async {
      final repo = FakeVerificationRepo(expiryMinutes: 15, currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      final service = VerificationServiceImpl(
        providers: {'manual': manual},
        repo: repo,
      );

      final req = await service.request(orderId: 'order-1', phone: '+201000000001');
      expect(req.orderId, 'order-1');
      expect(req.phone, '+201000000001');
      expect(req.status, VerificationStatus.pending);
      expect(req.provider, 'manual');
      expect(req.expiresAt, isNotNull);
      final diff = req.expiresAt!.difference(req.createdAt ?? DateTime.now().toUtc());
      expect(diff.inMinutes, 15);
      // code_hash never plaintext — even manual uses placeholder hash
      final hash = repo.codeHashFor('order-1');
      expect(hash, isNotNull);
      expect(hash, isNotEmpty);
      expect(hash, isNot('123456'));
      expect(hash, isNot(req.phone));
    });

    test('request is idempotent — second request returns same pending', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      final service = VerificationServiceImpl(providers: {'manual': manual}, repo: repo);

      final first = await service.request(orderId: 'order-2', phone: '+201000000002');
      final second = await service.request(orderId: 'order-2', phone: '+201000000002');
      expect(second.id, first.id);
      expect(second.status, VerificationStatus.pending);
    });
  });

  group('Manual verifyCode always false until staff confirms', () {
    test('verify with manual returns false even with any code', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      final service = VerificationServiceImpl(providers: {'manual': manual}, repo: repo);

      await service.request(orderId: 'order-3', phone: '+201000000003');
      final ok = await service.verify(orderId: 'order-3', code: '123456');
      expect(ok, isFalse);
      final ok2 = await service.verify(orderId: 'order-3', code: '000000');
      expect(ok2, isFalse);
      // Still pending
      final req = await repo.fetchByOrderId('order-3');
      expect(req!.status, VerificationStatus.pending);
      expect(req.attempts, 2); // incremented on each false verify
    });

    test('staff confirmByStaff lifts pending to confirmed and verify still false (replay)', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      final service = VerificationServiceImpl(providers: {'manual': manual}, repo: repo);

      await service.request(orderId: 'order-4', phone: '+201000000004');
      // verify should be false before confirm
      expect(await service.verify(orderId: 'order-4', code: 'any'), isFalse);

      await service.confirmByStaff(orderId: 'order-4');
      final after = await repo.fetchByOrderId('order-4');
      expect(after!.status, VerificationStatus.confirmed);
      // code_hash invalidated (NULL) after confirmed — spec
      expect(repo.codeHashFor('order-4'), anyOf(isNull, isEmpty, ''));

      // replay of verify after confirmed returns false (spec: replay returns false)
      final replay = await service.verify(orderId: 'order-4', code: 'any');
      expect(replay, isFalse);
    });

    test('rejectByStaff flips to rejected and order would be cancelled (via gate)', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      final service = VerificationServiceImpl(providers: {'manual': manual}, repo: repo);

      await service.request(orderId: 'order-5', phone: '+201000000005');
      await service.rejectByStaff(orderId: 'order-5');
      final after = await repo.fetchByOrderId('order-5');
      expect(after!.status, VerificationStatus.rejected);
      expect(repo.codeHashFor('order-5'), anyOf(isNull, isEmpty, ''));
    });
  });

  group('Expired request cannot be confirmed', () {
    test('expired pending blocks confirmByStaff', () async {
      final repo = FakeVerificationRepo(expiryMinutes: 15, currentRole: 'staff');
      // Seed an already-expired request
      final expiredAt = DateTime.now().toUtc().subtract(const Duration(minutes: 20));
      final pastReq = VerificationRequest(
        id: 'vr_expired',
        orderId: 'order-exp',
        phone: '+201000000006',
        status: VerificationStatus.pending,
        provider: 'manual',
        expiresAt: expiredAt,
        attempts: 0,
        createdAt: expiredAt.subtract(const Duration(minutes: 15)),
      );
      repo.seedRequest(pastReq, codeHash: 'sha256_expired_hash');

      // Verify returns false due to expiry, not exception (spec)
      final verifyExpired = await repo.verifyCode(orderId: 'order-exp', code: '123456');
      expect(verifyExpired, isFalse);
      final afterVerify = await repo.fetchByOrderId('order-exp');
      expect(afterVerify!.status, VerificationStatus.expired);

      // Confirm should be blocked — our fake throws StateError for expired
      await expectLater(
        repo.confirmByStaff(orderId: 'order-exp'),
        throwsA(isA<StateError>()),
      );
    });

    test('expired verify returns false not exception, increments to expired after max attempts', () async {
      final repo = FakeVerificationRepo(defaultMaxAttempts: 2, currentRole: 'staff');
      await repo.requestVerification(orderId: 'order-attempts', phone: '+201000000007');
      // Two wrong codes → expire
      expect(await repo.verifyCode(orderId: 'order-attempts', code: 'wrong1'), isFalse);
      expect(await repo.verifyCode(orderId: 'order-attempts', code: 'wrong2'), isFalse);
      final after = await repo.fetchByOrderId('order-attempts');
      expect(after!.status, VerificationStatus.expired);
      expect(after.attempts, 2);
      // Further verify still false
      expect(await repo.verifyCode(orderId: 'order-attempts', code: 'wrong3'), isFalse);
    });
  });

  group('Double-confirm idempotent', () {
    test('second confirm does not throw and stays confirmed', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      final service = VerificationServiceImpl(providers: {'manual': manual}, repo: repo);

      await service.request(orderId: 'order-dbl', phone: '+201000000008');
      await service.confirmByStaff(orderId: 'order-dbl');
      final first = await repo.fetchByOrderId('order-dbl');
      expect(first!.status, VerificationStatus.confirmed);

      // Second confirm — idempotent, no exception, still confirmed, no duplicate side effects
      await service.confirmByStaff(orderId: 'order-dbl');
      final second = await repo.fetchByOrderId('order-dbl');
      expect(second!.status, VerificationStatus.confirmed);
      expect(second.id, first.id);
    });

    test('double-reject idempotent', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      await repo.requestVerification(orderId: 'order-dbl-r', phone: '+201000000009');
      await repo.rejectByStaff(orderId: 'order-dbl-r');
      await repo.rejectByStaff(orderId: 'order-dbl-r');
      final after = await repo.fetchByOrderId('order-dbl-r');
      expect(after!.status, VerificationStatus.rejected);
    });
  });

  group('Plaintext code never stored — code_hash != code', () {
    test('code_hash is hashed placeholder, not equal to plaintext code', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      await repo.requestVerification(orderId: 'order-plain', phone: '+201000000010', provider: 'manual');
      final hash = repo.codeHashFor('order-plain');
      expect(hash, isNotNull);
      expect(hash, isNot('plain123'));
      expect(hash, isNot('manual'));
      expect(hash!.contains('plain123'), isFalse);
      // Even if we try to guess the placeholder, it contains hash prefix
      expect(hash.startsWith('sha256_'), isTrue);
    });

    test('verify with correct code would match hash but manual placeholder never matches any code', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      String fakeHash(String s) {
        final bytes = s.codeUnits;
        var h = 0;
        for (final b in bytes) {
          h = ((h << 5) - h) + b;
          h &= 0xFFFFFFFF;
        }
        return 'sha256_${h.toRadixString(16)}_${bytes.length}';
      }

      final orderId = 'order-real';
      await repo.requestVerification(orderId: orderId, phone: '+201000000011');
      final pending = await repo.fetchByOrderId(orderId);
      repo.clear();
      repo.seedRequest(
        VerificationRequest(
          id: 'vr_real',
          orderId: orderId,
          phone: '+201000000011',
          status: VerificationStatus.pending,
          provider: 'manual',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
          attempts: 0,
          createdAt: DateTime.now().toUtc(),
        ),
        codeHash: fakeHash('secret123'),
      );
      final ok = await repo.verifyCode(orderId: orderId, code: 'secret123');
      expect(ok, isTrue);
      expect(repo.codeHashFor(orderId), isNot('secret123'));
      expect(pending, isNotNull);
    });
  });

  group('Provider seam — manual provider uses repo, WhatsApp can be added later', () {
    test('ManualVerificationProvider delegates to repo', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      final req = await manual.requestVerification(orderId: 'order-prov', phone: '+201000000012');
      expect(req.provider, 'manual');
      expect(req.status, VerificationStatus.pending);
      // Verify via provider also goes to repo
      final ok = await manual.verifyCode(orderId: 'order-prov', code: 'any');
      expect(ok, isFalse);
      await manual.cancelVerification(orderId: 'order-prov');
      final after = await repo.fetchByOrderId('order-prov');
      expect(after!.status, VerificationStatus.cancelled);
    });

    test('VerificationService selects provider by name', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      // Simulate WhatsApp provider stub
      final fakeWhats = _FakeWhatsProvider(repo);
      final service = VerificationServiceImpl(
        providers: {'manual': manual, 'whatsapp': fakeWhats},
        repo: repo,
      );
      final r1 = await service.request(orderId: 'o-m', phone: '+201000000013', provider: 'manual');
      expect(r1.provider, 'manual');
      final r2 = await service.request(orderId: 'o-w', phone: '+201000000014', provider: 'whatsapp');
      expect(r2.provider, 'whatsapp');
    });
  });
}

// Fake WhatsApp provider for seam test — just creates with whatsapp provider name
class _FakeWhatsProvider implements VerificationProvider {
  _FakeWhatsProvider(this._repo);
  final FakeVerificationRepo _repo;
  @override
  Future<VerificationRequest> requestVerification({required String orderId, required String phone}) =>
      _repo.requestVerification(orderId: orderId, phone: phone, provider: 'whatsapp');
  @override
  Future<bool> verifyCode({required String orderId, required String code}) => _repo.verifyCode(orderId: orderId, code: code);
  @override
  Future<void> cancelVerification({required String orderId}) => _repo.cancelVerification(orderId: orderId);
}
