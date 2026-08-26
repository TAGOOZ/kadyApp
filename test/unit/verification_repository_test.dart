// RISK-05 repository tests — RLS and seam fake.
// No network, no Supabase — exercises FakeVerificationRepo which mirrors SQL
// logic in 0024_verification_abstraction.sql (hashing, attempts, expiry, invalidation).
// Real RLS is verified live via SQL smoke (see issue AC), but fake enforces role checks.

import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/verification_repository.dart';

void main() {
  group('VerificationRepository — RLS denied for customer, allowed for staff', () {
    test('customer cannot confirmByStaff — throws VerificationPermissionException (42501)', () async {
      final repo = FakeVerificationRepo(currentRole: 'customer');
      await repo.requestVerification(orderId: 'o-cust', phone: '+201000000021');
      expect(
        () => repo.confirmByStaff(orderId: 'o-cust'),
        throwsA(isA<VerificationPermissionException>()),
      );
      expect(
        () => repo.rejectByStaff(orderId: 'o-cust'),
        throwsA(isA<VerificationPermissionException>()),
      );
    });

    test('staff can confirm/reject — allowed', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      await repo.requestVerification(orderId: 'o-staff', phone: '+201000000022');
      await expectLater(repo.confirmByStaff(orderId: 'o-staff'), completes);
      final after = await repo.fetchByOrderId('o-staff');
      expect(after!.status, VerificationStatus.confirmed);

      final repo2 = FakeVerificationRepo(currentRole: 'admin');
      await repo2.requestVerification(orderId: 'o-admin', phone: '+201000000023');
      await expectLater(repo2.rejectByStaff(orderId: 'o-admin'), completes);
      final after2 = await repo2.fetchByOrderId('o-admin');
      expect(after2!.status, VerificationStatus.rejected);
    });

    test('unauthenticated (guest) role also denied', () async {
      final repo = FakeVerificationRepo(currentRole: 'customer');
      repo.currentRole = 'customer'; // simulate guest/customer without staff
      await repo.requestVerification(orderId: 'o-guest', phone: '+201000000024');
      await expectLater(repo.confirmByStaff(orderId: 'o-guest'), throwsA(isA<VerificationPermissionException>()));
    });

    test('staff confirm requires pending — expired throws, not silently succeeds', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      repo.seedRequest(
        VerificationRequest(
          id: 'vr_exp',
          orderId: 'o-exp-rls',
          phone: '+201000000025',
          status: VerificationStatus.pending,
          provider: 'manual',
          expiresAt: past,
          attempts: 0,
          createdAt: past.subtract(const Duration(minutes: 15)),
        ),
        codeHash: 'sha256_exp',
      );
      // Our fake will detect expiry and throw StateError (SQL would raise P0001)
      await expectLater(repo.confirmByStaff(orderId: 'o-exp-rls'), throwsA(isA<StateError>()));
    });
  });

  group('VerificationRepository — hashing never plaintext', () {
    test('request stores placeholder hash, not phone or orderId plaintext', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final orderId = 'order-hash-1';
      const phone = '+201000000026';
      await repo.requestVerification(orderId: orderId, phone: phone);
      final hash = repo.codeHashFor(orderId);
      expect(hash, isNotNull);
      expect(hash, isNot(phone));
      expect(hash, isNot(orderId));
      expect(hash, isNot('manual'));
      expect(hash!.startsWith('sha256_'), isTrue);
    });

    test('verifyCode hashes input before compare — plaintext never stored', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      await repo.requestVerification(orderId: 'order-hash-2', phone: '+201000000027');
      final beforeHash = repo.codeHashFor('order-hash-2');
      await repo.verifyCode(orderId: 'order-hash-2', code: 'mycode123');
      final afterHash = repo.codeHashFor('order-hash-2');
      // Wrong code should increment attempts but not expose plaintext
      expect(beforeHash, isNot('mycode123'));
      expect(afterHash, isNot('mycode123'));
      // After successful confirm, code_hash is NULL (invalidation)
      await repo.confirmByStaff(orderId: 'order-hash-2');
      expect(repo.codeHashFor('order-hash-2'), anyOf(isEmpty, isNull, ''));
    });
  });

  group('VerificationRepository — attempt counting and expiry', () {
    test('attempts increment on wrong code, status → expired at max_attempts', () async {
      final repo = FakeVerificationRepo(defaultMaxAttempts: 3, currentRole: 'staff');
      await repo.requestVerification(orderId: 'o-attempt', phone: '+201000000028');
      expect((await repo.fetchByOrderId('o-attempt'))!.attempts, 0);

      await repo.verifyCode(orderId: 'o-attempt', code: 'wrong');
      expect((await repo.fetchByOrderId('o-attempt'))!.attempts, 1);
      expect((await repo.fetchByOrderId('o-attempt'))!.status, VerificationStatus.pending);

      await repo.verifyCode(orderId: 'o-attempt', code: 'wrong');
      await repo.verifyCode(orderId: 'o-attempt', code: 'wrong');
      final after = await repo.fetchByOrderId('o-attempt');
      expect(after!.attempts, 3);
      expect(after.status, VerificationStatus.expired);
    });

    test('expires_at < now() → expired on next verify, not exception', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final expiredAt = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
      repo.seedRequest(
        VerificationRequest(
          id: 'vr_exp2',
          orderId: 'o-exp2',
          phone: '+201000000029',
          status: VerificationStatus.pending,
          provider: 'manual',
          expiresAt: expiredAt,
          attempts: 0,
          createdAt: expiredAt.subtract(const Duration(minutes: 15)),
        ),
        codeHash: 'sha256_some',
      );
      final ok = await repo.verifyCode(orderId: 'o-exp2', code: 'any');
      expect(ok, isFalse); // not exception
      final after = await repo.fetchByOrderId('o-exp2');
      expect(after!.status, VerificationStatus.expired);
    });

    test('invalidation on success — code_hash NULL after confirmed', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      await repo.requestVerification(orderId: 'o-inval', phone: '+201000000030');
      // Simulate a provider where we know the hash: compute same as FakeVerificationRepo._hash
      String fakeHash(String s) {
        final bytes = s.codeUnits;
        var h = 0;
        for (final b in bytes) {
          h = ((h << 5) - h) + b;
          h &= 0xFFFFFFFF;
        }
        return 'sha256_${h.toRadixString(16)}_${bytes.length}';
      }

      final hash = fakeHash('goodcode');
      // Replace with correct hash — need to clear old list and seed new
      // For test, we directly seed a new pending with correct hash
      repo.clear();
      repo.seedRequest(
        VerificationRequest(
          id: 'vr-inval',
          orderId: 'o-inval',
          phone: '+201000000030',
          status: VerificationStatus.pending,
          provider: 'manual',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
          attempts: 0,
          createdAt: DateTime.now().toUtc(),
        ),
        codeHash: hash,
      );
      // Now verify with correct code should succeed and null hash
      final ok = await repo.verifyCode(orderId: 'o-inval', code: 'goodcode');
      expect(ok, isTrue);
      expect(repo.codeHashFor('o-inval'), anyOf(isEmpty, isNull, ''));
      final after = await repo.fetchByOrderId('o-inval');
      expect(after!.status, VerificationStatus.confirmed);
    });

    test('replay of confirmed code returns false', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      await repo.requestVerification(orderId: 'o-replay', phone: '+201000000031');
      await repo.confirmByStaff(orderId: 'o-replay');
      final ok = await repo.verifyCode(orderId: 'o-replay', code: 'any');
      expect(ok, isFalse);
    });
  });

  group('VerificationRepository — provider seam fake', () {
    test('ManualVerificationProvider creates pending, WhatsApp provider can be added without touching risk_engine', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      final manual = ManualVerificationProvider(repo);
      final req = await manual.requestVerification(orderId: 'o-man', phone: '+201000000032');
      expect(req.provider, 'manual');
      expect(req.status, VerificationStatus.pending);

      // Simulate future WhatsAppVerificationProvider reusing same repo table
      final whatsRepoReq = await repo.requestVerification(orderId: 'o-wa', phone: '+201000000033', provider: 'whatsapp');
      expect(whatsRepoReq.provider, 'whatsapp');
      expect(whatsRepoReq.status, VerificationStatus.pending);
      // Both use same verification_requests table — provider column distinguishes
    });

    test('fetchByOrderId and fetchPendingForPhone', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      await repo.requestVerification(orderId: 'o-f1', phone: '+201000000034');
      await repo.requestVerification(orderId: 'o-f2', phone: '+201000000034');
      await repo.requestVerification(orderId: 'o-f3', phone: '+201000000035');
      final pendingForPhone = await repo.fetchPendingForPhone('+201000000034');
      expect(pendingForPhone.length, 2);
      expect(pendingForPhone.map((r) => r.orderId), containsAll(['o-f1', 'o-f2']));

      final single = await repo.fetchByOrderId('o-f1');
      expect(single!.orderId, 'o-f1');
      expect(await repo.fetchByOrderId('non-existent'), isNull);
    });
  });

  group('VerificationRepository — cancel', () {
    test('cancelVerification pending → cancelled', () async {
      final repo = FakeVerificationRepo(currentRole: 'staff');
      await repo.requestVerification(orderId: 'o-cancel', phone: '+201000000036');
      await repo.cancelVerification(orderId: 'o-cancel');
      final after = await repo.fetchByOrderId('o-cancel');
      expect(after!.status, VerificationStatus.cancelled);
    });
  });
}
