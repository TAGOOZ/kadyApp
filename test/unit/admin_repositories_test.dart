// Unit tests for the admin repositories (#015): KPI math, campaign toggle
// payload (+ double-window flag), rules jsonb encoding, menu CRUD payloads —
// against an in-memory fake db seam.
import 'package:flutter_test/flutter_test.dart';
import 'package:kady_app/data/repos/admin_repositories.dart';

class RecordedOp {
  const RecordedOp(this.op, this.table, this.values,
      {this.whereColumn, this.whereValue, this.onConflict});
  final String op;
  final String table;
  final Map<String, dynamic> values;
  final String? whereColumn;
  final Object? whereValue;
  final String? onConflict;
}

class FakeAdminDb implements AdminDbClient {
  FakeAdminDb({Map<String, List<Map<String, dynamic>>>? tables})
      : tables = tables ?? {};

  /// Scripted SELECT results keyed by table name.
  final Map<String, List<Map<String, dynamic>>> tables;

  /// Scripted head-count results keyed by table name; falls back to
  /// filtering [tables] client-side.
  final Map<String, int> scriptedCounts = {};
  final List<RecordedOp> ops = [];
  bool denyReads = false;

  Never _denied() => throw const AdminAccessDeniedException();

  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    List<({String column, Object value})> eq = const [],
    ({String column, Object value})? gte,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    if (denyReads) _denied();
    ops.add(RecordedOp('select', table, {
      'columns': columns,
      if (gte != null) 'gte': '${gte.column}@${gte.value}',
    }));
    return [for (final row in tables[table] ?? const []) Map.of(row)];
  }

  @override
  Future<int> count(
    String table, {
    List<({String column, Object value})> eq = const [],
    ({String column, Object value})? gte,
  }) async {
    if (denyReads) _denied();
    ops.add(RecordedOp('count', table, {
      if (gte != null) 'gte': '${gte.column}@${gte.value}',
      'eq': [for (final f in eq) '${f.column}@${f.value}'],
    }));
    final scripted = scriptedCounts[table];
    if (scripted != null) return scripted;
    return _filterRows(tables[table] ?? const [], eq: eq, gte: gte).length;
  }

  static List<Map<String, dynamic>> _filterRows(
    List<Map<String, dynamic>> rows, {
    required List<({String column, Object value})> eq,
    required ({String column, Object value})? gte,
  }) {
    DateTime? asDate(Object? v) =>
        v is DateTime ? v : v is String ? DateTime.tryParse(v) : null;
    return [
      for (final row in rows)
        if (eq.every((f) => row[f.column] == f.value))
          if (gte == null ||
              (asDate(row[gte.column]) != null &&
                  asDate(gte.value) != null &&
                  !asDate(row[gte.column])!.isBefore(asDate(gte.value)!)))
            row
    ];
  }

  @override
  Future<void> insert(String table, Map<String, dynamic> values) async {
    ops.add(RecordedOp('insert', table, values));
  }

  @override
  Future<void> update(
    String table,
    Map<String, dynamic> values, {
    required String whereColumn,
    required Object whereValue,
  }) async {
    ops.add(RecordedOp(
      'update',
      table,
      values,
      whereColumn: whereColumn,
      whereValue: whereValue,
    ));
  }

  @override
  Future<void> upsert(
    String table,
    Map<String, dynamic> values, {
    String onConflict = 'id',
  }) async {
    ops.add(RecordedOp('upsert', table, values, onConflict: onConflict));
  }

  @override
  Future<void> delete(
    String table, {
    required String whereColumn,
    required Object whereValue,
  }) async {
    ops.add(RecordedOp(
      'delete',
      table,
      const {},
      whereColumn: whereColumn,
      whereValue: whereValue,
    ));
  }

  Iterable<RecordedOp> where(String op, String table) =>
      ops.where((o) => o.op == op && o.table == table);
}

void main() {
  final kpiRows = [
    // Today — phone A.
    {
      'phone': '01000000001',
      'subtotal': 50,
      'total': null,
      'created_at': '2026-08-23T09:00:00Z',
    },
    // Yesterday — phone A again (still one distinct Customer).
    {
      'phone': '01000000001',
      'subtotal': 70,
      'total': 85,
      'created_at': '2026-08-22T20:00:00Z',
    },
    // Today — phone B.
    {
      'phone': '01000000002',
      'subtotal': 100,
      'total': 115,
      'created_at': '2026-08-23T11:00:00Z',
    },
    // Guest order without phone.
    {
      'phone': null,
      'subtotal': 30,
      'total': 45,
      'created_at': '2026-08-23T12:00:00Z',
    },
  ];

  group('KPI pure math over bounded rows', () {
    test('distinct-phone reach ignores guests and duplicates', () {
      expect(distinctPhones(kpiRows), 2);
      expect(distinctPhones(const []), 0);
    });

    test('mean basket = total ?? subtotal across every priced row', () {
      // Basket = total ?? subtotal over every priced row: 50 + 85 + 115 + 45.
      expect(averageBasketEgp(kpiRows), closeTo(295 / 4, 0.001));
      expect(averageBasketEgp(const []), 0);
    });
  });

  group('AdminKpiRepository.fetchKpis — bounded probes (audit #6)', () {
    test('today rides a head-count; reach + basket are 30-day selects',
        () async {
      final db = FakeAdminDb(tables: {'orders': kpiRows})
        ..scriptedCounts['orders'] = 3;
      final now = DateTime(2026, 8, 23, 18, 30);

      final kpis = await AdminKpiRepository(db).fetchKpis(now);

      expect(kpis.ordersToday, 3);
      expect(kpis.activeCustomers, 2);
      expect(kpis.avgBasketEgp, closeTo(295 / 4, 0.001));

      // Exactly one head-count probe, gte-bounded to the local day start.
      final counts = db.where('count', 'orders').toList();
      expect(counts, hasLength(1));
      expect(counts.single.values['gte'], startsWith('created_at@2026-08-2'));

      // Two windowed selects with column-bounded payloads (no `*`).
      final selects = db.where('select', 'orders').toList();
      expect(selects, hasLength(2));
      expect(selects.map((s) => s.values['columns']), contains('phone'));
      expect(
          selects.map((s) => s.values['columns']),
          contains('subtotal, total'));
      for (final s in selects) {
        expect(s.values['columns'], isNot('*'));
        expect(s.values['gte'], startsWith('created_at@2026-07-'));
      }
    });

    test('empty window degrades to zeros', () async {
      final db = FakeAdminDb()..scriptedCounts['orders'] = 0;

      final kpis =
          await AdminKpiRepository(db).fetchKpis(DateTime(2026, 8, 23));

      expect(kpis.ordersToday, 0);
      expect(kpis.activeCustomers, 0);
      expect(kpis.avgBasketEgp, 0);
    });

    test('unscripted count derives from seeded rows via the day-start filter',
        () async {
      final db = FakeAdminDb(tables: {'orders': kpiRows});

      final kpis =
          await AdminKpiRepository(db).fetchKpis(DateTime(2026, 8, 23));

      // Only the three same-day rows count toward orders-today.
      expect(kpis.ordersToday, 3);
    });
  });

  group('mode share / top item', () {
    test('counts modes and aggregates items qty across orders', () {
      final rows = [
        {
          'mode': 'dine_in',
          'items': [
            {'name_ar': 'لاتيه', 'qty': 2},
            {'name_ar': 'كرواسون', 'qty': 1},
          ],
        },
        {
          'mode': 'dine_in',
          'items': [
            {'name_ar': 'لاتيه', 'qty': 1},
          ],
        },
        {'mode': 'pickup', 'items': []},
        {'mode': 'delivery', 'items': null},
      ];

      expect(computeModeCounts(rows),
          {'dine_in': 2, 'pickup': 1, 'delivery': 1});

      final top = computeTopItem(rows);
      expect(top, isNotNull);
      expect(top!.nameAr, 'لاتيه');
      expect(top.qty, 3);
    });

    test('no rows → zero counts and null top item', () {
      expect(computeModeCounts(const []),
          {'dine_in': 0, 'pickup': 0, 'delivery': 0});
      expect(computeTopItem(const []), isNull);
    });
  });

  group('campaign repository', () {
    test('toggleActive updates the row and flips the double-window flag',
        () async {
      final db = FakeAdminDb();
      final repo = CampaignRepository(db);
      const campaign = Campaign(
        id: 'c-1',
        kind: 'double_points',
        active: true,
        nameAr: 'ليل الماتش',
      );

      await repo.toggleActive(campaign, false);

      final update = db.where('update', 'campaigns').single;
      expect(update.values, {'active': false});
      expect(update.whereColumn, 'id');
      expect(update.whereValue, 'c-1');

      final flag = db.where('upsert', 'app_config').single;
      expect(flag.values['key'], 'double_window_active');
      expect(flag.values['value'], false);
      expect(flag.onConflict, 'key');
    });

    test('non-double campaigns do not touch app_config', () async {
      final db = FakeAdminDb();
      final repo = CampaignRepository(db);
      const campaign = Campaign(id: 'c-2', kind: 'ramadan', active: false);

      await repo.toggleActive(campaign, true);

      expect(db.where('update', 'campaigns').single.values, {'active': true});
      expect(db.where('upsert', 'app_config'), isEmpty);
    });

    test('create sends kind/name/dates without id', () async {
      final db = FakeAdminDb();
      final repo = CampaignRepository(db);

      await repo.create(
        kind: 'exam_season',
        nameAr: 'موسم الامتحانات',
        startsAt: DateTime.utc(2026, 12, 1),
      );

      final insert = db.where('insert', 'campaigns').single;
      expect(insert.values['kind'], 'exam_season');
      expect(insert.values['name_ar'], 'موسم الامتحانات');
      expect(insert.values['starts_at'], contains('2026-12-01'));
      expect(insert.values.containsKey('id'), isFalse);
      expect(insert.values.containsKey('ends_at'), isFalse);
    });

    test('listAll orders by kind and parses rows', () async {
      final db = FakeAdminDb(tables: {
        'campaigns': [
          {
            'id': 'c-9',
            'kind': 'ramadan',
            'active': true,
            'name_ar': 'رمضان كريم',
            'starts_at': '2026-02-17T00:00:00Z',
            'ends_at': null,
          },
        ],
      });
      final repo = CampaignRepository(db);

      final campaigns = await repo.listAll();

      expect(campaigns.single.id, 'c-9');
      expect(campaigns.single.nameAr, 'رمضان كريم');
      expect(campaigns.single.startsAt, isNotNull);
      expect(campaigns.single.endsAt, isNull);
      expect(db.ops.single.values['columns'], '*');
    });
  });

  group('rules repository', () {
    test('save upserts key/value jsonb pair on conflict key', () async {
      final db = FakeAdminDb();
      final repo = RulesRepository(db);

      await repo.save('points_per_10egp', 2);
      await repo.save('dine_in_multiplier', 1.25);

      final saves = db.where('upsert', 'app_config').toList();
      expect(saves[0].values,
          {'key': 'points_per_10egp', 'value': 2});
      expect(saves[0].onConflict, 'key');
      // Doubles survive intact (jsonb numeric).
      expect(saves[1].values['value'], 1.25);
    });

    test('fetchAll flattens rows into {key: value}', () async {
      final db = FakeAdminDb(tables: {
        'app_config': [
          {'key': 'delivery_fee', 'value': 15},
          {'key': 'tier_gold', 'value': 5000},
        ],
      });

      final values = await RulesRepository(db).fetchAll();

      expect(values['delivery_fee'], 15);
      expect(values['tier_gold'], 5000);
    });
  });

  group('menu repository', () {
    Map<String, dynamic> latteRow() => {
        'id': 'm-1',
        'slug': 'latte',
        'category_id': 3,
        'menu_categories': {
          'id': 3,
          'slug': 'hot_drinks',
          'name_ar': 'مشروبات ساخنة',
          'name_en': 'Hot Drinks',
        },
        'name_ar': 'لاتيه',
        'name_en': 'Latte',
        'desc_ar': 'حليب وإسبريسو',
        'desc_en': 'Milk and espresso',
        'price_egp': 45,
        'is_available': true,
        'sort': 2,
      };

  AdminMenuItem rowItem() => AdminMenuItem.fromRow(latteRow());

    test('fromRow parses joined category; payload keeps category_id', () {
      final item = rowItem();
      expect(item.categorySlug, 'hot_drinks');
      expect(item.categoryId, 3);

      final payload = item.toPayload();
      expect(payload['id'], 'm-1');
      expect(payload['slug'], 'latte');
      expect(payload['category_id'], 3);
      expect(payload['price_egp'], 45);
      expect(payload['is_available'], true);
    });

    test('upsertItem insert omits id, update carries it', () async {
      final db = FakeAdminDb();
      final repo = AdminMenuRepository(db);
      const draft = MenuItemDraft(
        slug: 'flat-white-x1',
        nameAr: 'فلات وايت',
        nameEn: 'Flat White',
        descAr: '',
        descEn: '',
        priceEgp: 55,
        categoryId: 3,
        sort: 4,
      );

      await repo.upsertItem(draft);
      await repo.upsertItem(draft, id: 'm-2');

      final inserts = db.where('upsert', 'menu_items').toList();
      expect(inserts[0].values.containsKey('id'), isFalse);
      expect(inserts[0].values['slug'], 'flat-white-x1');
      expect(inserts[0].values['price_egp'], 55);
      expect(inserts[1].values['id'], 'm-2');
    });

    test('setAvailability / deleteItem / reinsertRow hit the right targets',
        () async {
      final db = FakeAdminDb();
      final repo = AdminMenuRepository(db);

      await repo.setAvailability('m-1', false);
      final update = db.where('update', 'menu_items').single;
      expect(update.values, {'is_available': false});
      expect(update.whereColumn, 'id');
      expect(update.whereValue, 'm-1');

      await repo.deleteItem('m-1');
      final del = db.where('delete', 'menu_items').single;
      expect(del.whereValue, 'm-1');

      final payload = rowItem().toPayload();
      await repo.reinsertRow(payload);
      final insert = db.where('insert', 'menu_items').single;
      expect(insert.values, payload);
    });

    test('generateSlug slugifies EN name with unique tail', () {
      final a = AdminMenuRepository.generateSlug('Iced Spanish Latte');
      final b = AdminMenuRepository.generateSlug('Iced Spanish Latte');
      expect(a.startsWith('iced-spanish-latte-'), isTrue);
      // Timestamp tail keeps the UNIQUE column happy.
      expect(a, isNot(b));
    });

    test('listCatalog groups categories and preserves join info', () async {
      final db = FakeAdminDb(tables: {
        'menu_items': [
          latteRow(),
        ],
      });

      final catalog = await AdminMenuRepository(db).listCatalog();

      expect(catalog.categories.single.slug, 'hot_drinks');
      expect(catalog.items.single.nameAr, 'لاتيه');
      expect(db.ops.single.values['columns'],
          contains('menu_categories(id, slug'));
    });
  });

  group('access-denied propagation', () {
    test('reads rethrow AdminAccessDeniedException instead of empty data',
        () async {
      final db = FakeAdminDb()..denyReads = true;

      await expectLater(
        AdminKpiRepository(db).fetchKpis(DateTime.now()),
        throwsA(isA<AdminAccessDeniedException>()),
      );
      await expectLater(
        CampaignRepository(db).listAll(),
        throwsA(isA<AdminAccessDeniedException>()),
      );
      await expectLater(
        RulesRepository(db).fetchAll(),
        throwsA(isA<AdminAccessDeniedException>()),
      );
    });
  });
}
