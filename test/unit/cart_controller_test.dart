// Cart math + merge semantics (issue #002 acceptance criteria).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kady_app/data/models/menu_models.dart';
import 'package:kady_app/domain/cart_controller.dart';

MenuItem _item(String id, int priceEgp) => MenuItem(
      id: id,
      slug: id,
      nameAr: 'لاتيه',
      nameEn: 'Latte',
      descAr: '',
      descEn: '',
      priceEgp: priceEgp,
      isAvailable: true,
      categorySlug: 'hot-drinks',
    );

void main() {
  late ProviderContainer container;
  late CartController cart;

  setUp(() {
    container = ProviderContainer();
    cart = container.read(cartProvider.notifier);
  });

  tearDown(() => container.dispose());

  group('addItem merge semantics', () {
    test('same item + same config merges into one line (qty 2)', () {
      const config = ItemConfig(sizeIndex: 0, sugarIndex: 2);
      final latte = _item('latte', 45);

      cart.addItem(latte, config);
      cart.addItem(latte, config);

      final lines = container.read(cartProvider);
      expect(lines, hasLength(1));
      expect(lines.single.qty, 2);
    });

    test('same item + different size stays two lines', () {
      final latte = _item('latte', 45);

      cart.addItem(latte, const ItemConfig(sizeIndex: 0));
      cart.addItem(latte, const ItemConfig(sizeIndex: 1));

      final lines = container.read(cartProvider);
      expect(lines, hasLength(2));
    });

    test('same size but different note stays two lines', () {
      final latte = _item('latte', 45);

      cart.addItem(latte, const ItemConfig(note: 'extra hot'));
      cart.addItem(latte, const ItemConfig());

      expect(container.read(cartProvider), hasLength(2));
    });

    test('addon set order does not affect identity', () {
      final latte = _item('latte', 45);

      cart.addItem(
        latte,
        const ItemConfig(addons: {'espresso_shot', 'caramel'}),
      );
      cart.addItem(
        latte,
        const ItemConfig(addons: {'caramel', 'espresso_shot'}),
        qty: 1,
      );

      final lines = container.read(cartProvider);
      expect(lines, hasLength(1));
      expect(lines.single.qty, 2);
    });
  });

  group('line total math', () {
    test('lineTotal = (base + sizeDelta + addons) * qty', () {
      // 45 base + 15 large + (15 espresso + 10 caramel) = 85 per unit.
      final line = CartLine(
        item: _item('latte', 45),
        config: const ItemConfig(
          sizeIndex: 2,
          addons: {'espresso_shot', 'caramel'},
        ),
        qty: 3,
      );

      expect(line.unitPriceEgp, 85);
      expect(line.lineTotalEgp, 255);
    });

    test('sugar level never changes the price', () {
      for (var sugar = 0; sugar < 3; sugar++) {
        final line = CartLine(
          item: _item('tea', 20),
          config: ItemConfig(sugarIndex: sugar),
          qty: 1,
        );
        expect(line.lineTotalEgp, 20);
      }
    });
  });

  group('subtotal / badge counters', () {
    test('subtotal sums line totals across lines', () {
      final latte = _item('latte', 45);
      final tea = _item('tea', 20);

      cart.addItem(latte, const ItemConfig(sizeIndex: 1), qty: 2); // 55*2=110
      cart.addItem(tea, const ItemConfig(), qty: 1); // 20

      expect(container.read(subtotalProvider), 130);
      expect(container.read(totalQuantityProvider), 3);
    });

    test('setQty updates math; qty 0 removes the line', () {
      final latte = _item('latte', 45);
      cart.addItem(latte, const ItemConfig(), qty: 1);
      var line = container.read(cartProvider).single;

      cart.setQty(line, 4);
      expect(container.read(subtotalProvider), 180);
      expect(container.read(totalQuantityProvider), 4);

      line = container.read(cartProvider).single;
      cart.setQty(line, 0);
      expect(container.read(cartProvider), isEmpty);
      expect(container.read(subtotalProvider), 0);
      expect(container.read(totalQuantityProvider), 0);
    });

    test('removeLine drops exactly the matching config line', () {
      final latte = _item('latte', 45);
      cart.addItem(latte, const ItemConfig(sizeIndex: 0));
      cart.addItem(latte, const ItemConfig(sizeIndex: 2));

      cart.removeLine(container.read(cartProvider).first);
      final lines = container.read(cartProvider);
      expect(lines, hasLength(1));
      expect(lines.single.config.sizeIndex, 2);
    });
  });

  test('favorites toggle is a session-scoped set', () {
    final favorites = container.read(favoritesProvider.notifier);
    favorites.toggle('latte');
    expect(container.read(favoritesProvider), {'latte'});
    favorites.toggle('latte');
    expect(container.read(favoritesProvider), isEmpty);
  });
}
