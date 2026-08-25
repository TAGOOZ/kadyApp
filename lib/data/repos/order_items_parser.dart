// Shared order items parser — deduplicates parseItemLines / OrderItemLine
// across StaffOrders and DriverOrders (ARCH-03). Canonical jsonb contract:
// `orders.items` is a List of Maps with `name_ar` and `qty`.

class OrderItemLine {
  const OrderItemLine({required this.name, required this.qty});

  final String name;
  final int qty;
}

List<OrderItemLine> parseItemLines(Object? itemsJson) {
  if (itemsJson is! List) return const [];
  return [
    for (final raw in itemsJson)
      if (raw is Map)
        OrderItemLine(
          name: (raw['name_ar'] as String?) ?? '',
          qty: raw['qty'] is num ? (raw['qty'] as num).toInt() : 1,
        ),
  ];
}

String itemsSummaryLine(List<OrderItemLine> lines, {String separator = ' · '}) {
  return [
    for (final line in lines) line.qty <= 1 ? line.name : '${line.name} ×${line.qty}',
  ].join(separator);
}
