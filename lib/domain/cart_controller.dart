// Cart state (issue #002): lines with merge semantics, subtotal and badge
// counters. No cart UI page yet — the menu tab badge consumes it.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/menu_models.dart';

class CartLine {
  const CartLine({
    required this.item,
    required this.config,
    required this.qty,
  });

  final MenuItem item;
  final ItemConfig config;
  final int qty;

  /// `(basePrice + sizeDelta + sum(addons))` — before quantity.
  int get unitPriceEgp =>
      item.priceEgp + config.sizeDeltaEgp + config.addonsTotalEgp;

  int get lineTotalEgp => unitPriceEgp * qty;

  CartLine copyWithQty(int qty) {
    return CartLine(item: item, config: config, qty: qty);
  }
}

class CartController extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => const [];

  /// Adds a line; merges into an existing line when item id + config identity
  /// (size/sugar/addons/note) match, so "same config twice" becomes qty 2.
  void addItem(MenuItem item, ItemConfig config, {int qty = 1}) {
    if (qty <= 0) return;
    final index = _indexOfLine(item.id, config);
    if (index == -1) {
      state = [...state, CartLine(item: item, config: config, qty: qty)];
      return;
    }
    final existing = state[index];
    final updated = [
      ...state.sublist(0, index),
      existing.copyWithQty(existing.qty + qty),
      ...state.sublist(index + 1),
    ];
    state = updated;
  }

  void removeLine(CartLine line) {
    final index = _indexOfLine(line.item.id, line.config);
    if (index != -1) {
      state = [...state]..removeAt(index);
    }
  }

  void setQty(CartLine line, int qty) {
    if (qty <= 0) {
      removeLine(line);
      return;
    }
    final index = _indexOfLine(line.item.id, line.config);
    if (index != -1) {
      final updated = [...state];
      updated[index] = updated[index].copyWithQty(qty);
      state = updated;
    }
  }

  int _indexOfLine(String itemId, ItemConfig config) {
    return state.indexWhere(
      (line) => line.item.id == itemId && line.config == config,
    );
  }
}

final cartProvider =
    NotifierProvider<CartController, List<CartLine>>(CartController.new);

final subtotalProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold(0, (sum, line) => sum + line.lineTotalEgp);
});

/// Drives the menu tab cart badge.
final totalQuantityProvider = Provider<int>((ref) {
  return ref.watch(cartProvider).fold(0, (sum, line) => sum + line.qty);
});

/// Session-scoped favorite item ids (in-memory for slice #002).
class FavoritesController extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String itemId) {
    final next = {...state};
    if (!next.remove(itemId)) {
      next.add(itemId);
    }
    state = next;
  }

  bool isFavorite(String itemId) => state.contains(itemId);
}

final favoritesProvider =
    NotifierProvider<FavoritesController, Set<String>>(FavoritesController.new);
