// Unit tests for the customer lookup slice (#013): search-term normalization
// (+20/space stripping for phone matching, raw term kept for names), manual
// reward payload builders (points vs voucher paths + staff_log audit shape),
// the typed permission mapping on 42501, visit registration pending-stamp
// mapping identical to the staff board, Cairo timestamp formatting, and the
// recent-searches store (dedupe/front-move/max 5). No network, no Supabase.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/customer_lookup_repository.dart';
import 'package:kady_app/data/repos/staff_orders_repository.dart';
import 'package:kady_app/domain/loyalty_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException;

class _FakeCustomerLookupDb implements CustomerLookupDb {
  final loyaltyUpdates = <MapEntry<String, Map<String, dynamic>>>[];
  final staffLogs = <Map<String, dynamic>>[];
  final visits = <Map<String, dynamic>>[];
  final stampWrites = <MapEntry<String, int>>[];

  String? searchedPhoneLike;
  String? searchedNameLike;
  Map<String, dynamic>? loyaltyRow;
  Object? loyaltyUpdateError;
  Object? stampUpdateError;

  // Visit-count probe recording (audit #7).
  String? visitsCountArg;
  int visitsCountResult = 0;

  @override
  Future<List<Map<String, dynamic>>> searchCustomers(
    String phoneLike,
    String nameLike,
  ) async {
    searchedPhoneLike = phoneLike;
    searchedNameLike = nameLike;
    return const [
      {'phone': '+201001234567', 'name': 'مصطفى كامل'},
      {'phone': '+201098765432', 'name': 'مصطفى ثاني'},
    ];
  }

  @override
  Future<Map<String, dynamic>?> fetchCustomer(String phone) async =>
      {'phone': phone, 'name': 'مصطفى كامل'};

  @override
  Future<Map<String, dynamic>?> fetchLoyalty(String phone) async =>
      loyaltyRow;

  @override
  Future<List<Map<String, dynamic>>> fetchRecentOrders(
    String phone,
    int limit,
  ) async => const [];

  @override
  Future<int> fetchVisitsCount(String phone) async {
    visitsCountArg = phone;
    return visitsCountResult;
  }

  @override
  Future<void> updateLoyalty(
      String phone, Map<String, dynamic> patch) async {
    final error = loyaltyUpdateError;
    if (error != null) throw error;
    loyaltyUpdates.add(MapEntry(phone, patch));
  }

  @override
  Future<void> insertStaffLog(Map<String, dynamic> row) async =>
      staffLogs.add(row);

  @override
  Future<List<Map<String, dynamic>>> fetchStaffLog(
    String phone,
    int limit,
  ) async => const [];

  @override
  Future<void> insertVisit(Map<String, dynamic> row) async =>
      visits.add(row);

  @override
  Future<int?> fetchStampMinSpend() async => 50;

  @override
  Future<int?> fetchStamps(String phone) async =>
      (loyaltyRow?['stamps'] as int?) ?? 3;

  @override
  Future<void> updateStamps(String phone, int stamps) async {
    final error = stampUpdateError;
    if (error != null) throw error;
    stampWrites.add(MapEntry(phone, stamps));
  }
}

void main() {
  group('normalizeSearchTerm — +20 / space variants', () {
    test('strips spaces and +20 from phone fragments', () {
      expect(normalizeSearchTerm('+20 100 123 4567'), '1001234567');
      expect(normalizeSearchTerm('+201001234567'), '1001234567');
      expect(normalizeSearchTerm(' 201001234567 '), '1001234567');
    });

    test('keeps plain digits and Arabic names intact', () {
      expect(normalizeSearchTerm('1001234567'), '1001234567');
      expect(normalizeSearchTerm('01001234567'), '01001234567');
      expect(normalizeSearchTerm('مصطفى'), 'مصطفى');
    });
  });

  group('repo.search — like-term plumbing', () {
    test('phone match uses the normalized term, name keeps spaces',
        () async {
      final db = _FakeCustomerLookupDb();
      final repo = SupabaseCustomerLookupRepo(db);

      final hits = await repo.search('+20 100 123 4567');

      expect(db.searchedPhoneLike, '%1001234567%');
      expect(db.searchedNameLike, '%+20 100 123 4567%');
      expect(hits, hasLength(2));
      expect(hits.first.phone, '+201001234567');
      expect(hits.first.name, 'مصطفى كامل');
    });

    test('blank terms short-circuit without hitting the db', () async {
      final db = _FakeCustomerLookupDb();
      expect(await SupabaseCustomerLookupRepo(db).search('   '), isEmpty);
      expect(db.searchedPhoneLike, isNull);
    });
  });

  group('manualRewardLoyaltyPatch — points vs voucher paths', () {
    final current = {
      'points': 120,
      'lifetime_points': 1500,
      'vouchers': [
        {'type': 'free_snack', 'at': '2026-08-01T10:00:00.000Z'},
      ],
    };

    test('points25 adds 25 to points AND lifetime (tier driver)', () {
      final patch = manualRewardLoyaltyPatch(
        current,
        const ManualRewardInput(
          type: ManualRewardType.points25,
          reason: ManualReason.lateApology,
        ),
      );
      expect(patch, {'points': 145, 'lifetime_points': 1525});
    });

    test('free_drink appends a {type, at} voucher, points untouched', () {
      final grantedAt = DateTime.utc(2026, 8, 22, 12);
      final patch = manualRewardLoyaltyPatch(
        current,
        const ManualRewardInput(
          type: ManualRewardType.freeDrink,
          reason: ManualReason.newGuest,
        ),
        grantedAtUtc: grantedAt,
      );
      expect(patch.containsKey('points'), isFalse);
      expect(patch['vouchers'], [
        {'type': 'free_snack', 'at': '2026-08-01T10:00:00.000Z'},
        {'type': 'free_drink', 'at': grantedAt.toIso8601String()},
      ]);
    });

    test('free_topping uses its own wire key', () {
      final patch = manualRewardLoyaltyPatch(
        current,
        const ManualRewardInput(
          type: ManualRewardType.freeTopping,
          reason: ManualReason.other,
        ),
        grantedAtUtc: DateTime.utc(2026, 8, 22),
      );
      expect((patch['vouchers'] as List).last,
          containsPair('type', 'free_topping'));
    });
  });

  group('manualRewardStaffLogRow — audit shape', () {
    test('actor staff, action manual_reward, detail jsonb payload', () {
      expect(
        manualRewardStaffLogRow(
          '+201001234567',
          const ManualRewardInput(
            type: ManualRewardType.points25,
            reason: ManualReason.lateApology,
            note: '  اتأخر الطلب نص ساعة ',
          ),
        ),
        {
          'actor': 'staff',
          'action': 'manual_reward',
          'target_phone': '+201001234567',
          'detail': {
            'reward': 'points25',
            'reason': 'late_apology',
            'note': 'اتأخر الطلب نص ساعة',
          },
        },
      );
    });

    test('blank notes are omitted from the detail jsonb', () {
      final row = manualRewardStaffLogRow(
        '+201001234567',
        const ManualRewardInput(
          type: ManualRewardType.freeDrink,
          reason: ManualReason.newGuest,
        ),
      );
      expect((row['detail'] as Map).containsKey('note'), isFalse);
    });
  });

  group('grantManualReward — update + best-effort audit + 42501', () {
    test('writes the loyalty patch then the staff_log row', () async {
      final db = _FakeCustomerLookupDb()
        ..loyaltyRow = {
          'points': 120,
          'lifetime_points': 1500,
          'vouchers': [],
        };
      final repo = SupabaseCustomerLookupRepo(db);

      await repo.grantManualReward(
        '+201001234567',
        const ManualRewardInput(
          type: ManualRewardType.points25,
          reason: ManualReason.lateApology,
        ),
      );

      expect(db.loyaltyUpdates.single.key, '+201001234567');
      expect(db.loyaltyUpdates.single.value,
          {'points': 145, 'lifetime_points': 1525});
      expect(db.staffLogs.single['action'], 'manual_reward');
      expect(db.staffLogs.single['target_phone'], '+201001234567');
    });

    test('RLS denial on the loyalty UPDATE surfaces typed', () async {
      final db = _FakeCustomerLookupDb()
        ..loyaltyRow = const {}
        ..loyaltyUpdateError =
            const PostgrestException(code: '42501', message: 'RLS');
      await expectLater(
        SupabaseCustomerLookupRepo(db).grantManualReward(
          '+201001234567',
          const ManualRewardInput(
            type: ManualRewardType.points25,
            reason: ManualReason.other,
          ),
        ),
        throwsA(isA<StaffPermissionException>()),
      );
      expect(db.staffLogs, isEmpty); // no audit line for denied grants
    });
  });

  group('registerVisit — same pending mapping as the staff board', () {
    test('qualifying spend stamps through when RLS allows', () async {
      final db = _FakeCustomerLookupDb()
        ..loyaltyRow = const {'stamps': 3};
      final result = await SupabaseCustomerLookupRepo(db).registerVisit(
        const CheckInInput(phone: '+201001234567', spendEgp: 60),
      );
      expect(result.loyaltyPending, isFalse);
      expect(db.visits.single['source'], 'checkin');
      expect(db.visits.single['spend_egp'], 60);
      expect(db.stampWrites.single.value, 4);
    });

    test('check-in on a full card completes it — writes 0, never 11+',
        () async {
      // Plan 002 unification: the persisted value respects the canonical
      // card rule (reaching 10 completes & resets) instead of raw +1.
      final db = _FakeCustomerLookupDb()..loyaltyRow = const {'stamps': 9};
      final result = await SupabaseCustomerLookupRepo(db).registerVisit(
        const CheckInInput(phone: '+201001234567', spendEgp: 60),
      );
      expect(result.loyaltyPending, isFalse);
      expect(db.stampWrites.single.value, 0); // completed card resets to 0
    });

    test('stamp write blocked by RLS → visit recorded, loyalty PENDING',
        () async {
      final db = _FakeCustomerLookupDb()
        ..loyaltyRow = const {'stamps': 3}
        ..stampUpdateError =
            const PostgrestException(code: '42501', message: 'RLS');
      final result = await SupabaseCustomerLookupRepo(db).registerVisit(
        const CheckInInput(phone: '+201001234567', spendEgp: 80),
      );
      expect(result.loyaltyPending, isTrue);
      expect(db.visits, hasLength(1));
    });

    test('below threshold skips the stamp entirely', () async {
      final db = _FakeCustomerLookupDb()..loyaltyRow = const {'stamps': 3};
      final result = await SupabaseCustomerLookupRepo(db).registerVisit(
        const CheckInInput(phone: '+201001234567', spendEgp: 20),
      );
      expect(result.loyaltyPending, isFalse);
      expect(db.stampWrites, isEmpty);
    });
  });

  group('loadProfile — visits count probe (audit #7)', () {
    test('profile carries the seam-provided count; phone is passed through',
        () async {
      final db = _FakeCustomerLookupDb()..visitsCountResult = 12;
      final repo = SupabaseCustomerLookupRepo(db);

      final profile = await repo.loadProfile('+201001234567');

      expect(db.visitsCountArg, '+201001234567');
      expect(profile.visits, 12);
      expect(profile.phone, '+201001234567');
    });
  });

  group('formatLookupWhenUtc — Cairo dd/MM HH:mm Western digits', () {
    test('summer timestamp renders Cairo local time', () {
      expect(
        formatLookupWhenUtc(DateTime.utc(2026, 8, 22, 10, 30)),
        '22/08 13:30',
      );
    });
  });

  group('RecentSearchStore — lookup.recent prefs', () {
    test('add moves to front, dedupes and caps at 5', () async {
      SharedPreferences.setMockInitialValues({
        'lookup.recent': ['لاتيه', 'كابتشينو', 'أسبريسو', 'فلات وايت', 'موكا'],
      });
      final store =
          RecentSearchStore(await SharedPreferences.getInstance());

      await store.add('لاتيه'); // existing → moved to front, no dup
      await store.add('كرواسون'); // newest → front, oldest (موكا) dropped

      expect(store.list(),
          ['كرواسون', 'لاتيه', 'كابتشينو', 'أسبريسو', 'فلات وايت']);
    });

    test('remove and clear mutate the persisted list', () async {
      SharedPreferences.setMockInitialValues({
        'lookup.recent': ['لاتيه', 'شاي'],
      });
      final prefs = await SharedPreferences.getInstance();
      final store = RecentSearchStore(prefs);

      await store.remove('لاتيه');
      expect(store.list(), ['شاي']);

      await store.clear();
      expect(store.list(), isEmpty);
      expect(prefs.getStringList(RecentSearchStore.key), isNull);
    });
  });

  group('derivedTier integration on profile lifetime points', () {
    test('tier chip source stays consistent with loyalty_controller', () {
      // Read-only guard: the card derives tiers from lifetime points.
      expect(derivedTier(1500), Tier.bronze);
      expect(derivedTier(2000), Tier.silver);
      expect(derivedTier(5000), Tier.gold);
    });
  });
}
