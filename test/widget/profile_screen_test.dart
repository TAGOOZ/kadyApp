// Widget tests for the profile tab (#011): authenticated rendering (name,
// gold tier chip, loyalty summary strip, vouchers, address card), the 4
// notification switches persisting to mocked prefs, the student toggle
// hitting updateProfile, delete-with-undo on addresses, and the guest-phase
// panel. No live network: auth/loyalty providers are stubbed and the repo
// seam is an in-memory fake.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kady_app/core/theme/app_theme.dart';
import 'package:kady_app/data/repos/address.dart';
import 'package:kady_app/data/repos/customers_repository.dart';
import 'package:kady_app/domain/auth_controller.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
import 'package:kady_app/ui/profile/profile_screen.dart';

class _StubAuth extends AuthController {
  _StubAuth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;
}

class _StubLoyalty extends LoyaltyController {
  _StubLoyalty(this.initial);

  final LoyaltyState initial;

  @override
  LoyaltyState build() => initial;
}

class _FakeProfileRepo implements CustomerProfileRepo {
  _FakeProfileRepo(this.profile, {List<AddressRecord>? addresses})
      : addresses = addresses ?? [];

  CustomerRecord profile;
  final List<AddressRecord> addresses;
  int updateCalls = 0;
  int addCalls = 0;
  int deleteCalls = 0;

  @override
  Future<CustomerRecord> loadByGoogleUserId(String googleUserId) async =>
      profile;

  @override
  Future<CustomerRecord> updateProfile({
    required String phone,
    required CustomerPatch patch,
  }) async {
    updateCalls++;
    profile = CustomerRecord(
      phone: phone,
      name: patch.name ?? profile.name,
      email: patch.email ?? profile.email,
      birthdate: patch.birthdate ?? profile.birthdate,
      isStudent: patch.isStudent ?? profile.isStudent,
      city: patch.city ?? profile.city,
    );
    return profile;
  }

  @override
  Future<List<AddressRecord>> listAddresses({
    required String googleUserId,
  }) async =>
      List.of(addresses);

  @override
  Future<AddressRecord> addAddress({
    required String googleUserId,
    required AddressLabel label,
    required String addressText,
    double? latitude,
    double? longitude,
  }) async {
    addCalls++;
    final record = AddressRecord(
      id: 'a${addresses.length + 1}',
      phone: profile.phone,
      label: label,
      addressText: addressText,
      latitude: latitude,
      longitude: longitude,
    );
    addresses.add(record);
    return record;
  }

  @override
  Future<AddressRecord> updateAddress({
    required AddressRecord address,
  }) async {
    final index = addresses.indexWhere((a) => a.id == address.id);
    addresses[index] = address;
    return address;
  }

  @override
  Future<void> deleteAddress({required String addressId}) async {
    deleteCalls++;
    addresses.removeWhere((a) => a.id == addressId);
  }
}

const _authed = AuthState(
  phase: AuthPhase.ready,
  googleUser: GoogleProfile(id: 'g-1', email: 'm@g.com', name: 'مصطفى'),
  phone: '+201001234567',
);

Future<void> _pump(
  WidgetTester tester, {
  required AuthState authState,
  LoyaltyState? loyaltyState,
  required CustomerProfileRepo repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _StubAuth(authState)),
        customerProfileRepoProvider.overrideWithValue(repo),
        if (loyaltyState != null)
          loyaltyProvider.overrideWith(() => _StubLoyalty(loyaltyState)),
      ],
      child: MaterialApp(
        theme: buildHeritageHearth(Brightness.light),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: ProfileScreen(),
        ),
      ),
    ),
  );
  // First frame = loading; second resolves the fake futures.
  await tester.pump();
  await tester.pump();
}

CustomerRecord get _seedProfile => CustomerRecord(
      phone: '+201001234567',
      name: 'مصطفى القاضي',
      birthdate: DateTime(2000, 1, 15),
      isStudent: true,
      city: 'القاهرة',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('authenticated: renders name, gold tier chip and summary strip',
      (tester) async {
    final repo = _FakeProfileRepo(_seedProfile);
    final loyalty = LoyaltyState(
      points: 1240,
      lifetimePoints: 5200,
      stamps: 7,
      vouchers: [
        Voucher(type: VoucherType.freeDrink, grantedAt: DateTime.utc(2026)),
      ],
    );
    await _pump(
      tester,
      authState: _authed,
      loyaltyState: loyalty,
      repo: repo,
    );

    // Name shows in both the header and the الاسم field row.
    expect(find.text('مصطفى القاضي'), findsNWidgets(2));
    expect(find.text('ذهبي'), findsOneWidget);
    expect(find.text('1240 نقطة · بطاقة 7/10'), findsOneWidget);
    // Vouchers section with status chip.
    expect(find.text('مشروب مجاني'), findsOneWidget);
    expect(find.text('صالحة'), findsOneWidget);
    // Phone row is read-only identity.
    expect(find.byKey(const Key('profile_row_phone')), findsOneWidget);
  });

  testWidgets('authenticated: address card renders from repo', (tester) async {
    final repo = _FakeProfileRepo(_seedProfile, addresses: [
      const AddressRecord(
        id: 'a1',
        phone: '+201001234567',
        label: AddressLabel.home,
        addressText: 'شارع التحرير، العمارة 5',
      ),
    ]);
    await _pump(tester, authState: _authed, repo: repo);

    expect(find.text('عناوين التوصيل'), findsOneWidget);
    expect(find.text('بيت'), findsOneWidget);
    expect(find.text('شارع التحرير، العمارة 5'), findsOneWidget);
    expect(find.text('إضافة عنوان'), findsOneWidget);
  });

  testWidgets('notification switches toggle and persist to prefs',
      (tester) async {
    final repo = _FakeProfileRepo(_seedProfile);
    await _pump(tester, authState: _authed, repo: repo);

    await tester.ensureVisible(find.byKey(const Key('profile_notif_orders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile_notif_orders')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('profile_notif_matches')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile_notif_matches')));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notifications.orders'), false);
    expect(prefs.getBool('notifications.matches'), false);
    // Untouched switches keep their in-memory default and write nothing.
    expect(prefs.getBool('notifications.offers'), isNull);
    expect(prefs.getBool('notifications.exams'), isNull);
  });

  testWidgets('student switch persists through updateProfile + snackbar',
      (tester) async {
    final repo = _FakeProfileRepo(_seedProfile);
    await _pump(tester, authState: _authed, repo: repo);

    await tester.ensureVisible(
        find.byKey(const Key('profile_row_student_switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile_row_student_switch')));
    await tester.pumpAndSettle();

    expect(repo.updateCalls, 1);
    expect(repo.profile.isStudent, false);
    expect(find.text('تم الحفظ ✓'), findsOneWidget);
  });

  testWidgets('address swipe-to-delete then undo restores it',
      (tester) async {
    final repo = _FakeProfileRepo(_seedProfile, addresses: [
      const AddressRecord(
        id: 'a1',
        phone: '+201001234567',
        label: AddressLabel.work,
        addressText: 'مكتب مدينة نصر',
      ),
    ]);
    await _pump(tester, authState: _authed, repo: repo);

    await tester.ensureVisible(find.text('مكتب مدينة نصر'));
    await tester.pumpAndSettle();
    // RTL: Dismissible endToStart = trailing(left) → leading(right) motion.
    await tester.drag(find.text('مكتب مدينة نصر'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(repo.deleteCalls, 1);
    expect(find.text('اتمسح العنوان'), findsOneWidget);

    await tester.tap(find.text('تراجع'));
    await tester.pumpAndSettle();
    expect(repo.addCalls, 1);
    expect(find.text('مكتب مدينة نصر'), findsOneWidget);
  });

  testWidgets('guest phase shows the Google sign-in panel instead of account',
      (tester) async {
    final repo = _FakeProfileRepo(_seedProfile);
    await _pump(
      tester,
      authState: const AuthState(phase: AuthPhase.guest),
      repo: repo,
    );

    expect(find.byKey(const Key('profile_guest_panel')), findsOneWidget);
    expect(find.byKey(const Key('profile_guest_google_button')), findsOneWidget);
    expect(find.text('سجّل بحساب Google'), findsOneWidget);
    // Account sections stay hidden.
    expect(find.text('بياناتي'), findsNothing);
    expect(find.text('عناوين التوصيل'), findsNothing);
    expect(find.byKey(const Key('profile_logout')), findsNothing);
    expect(find.byKey(const Key('profile_notif_orders')), findsNothing);
  });
}
