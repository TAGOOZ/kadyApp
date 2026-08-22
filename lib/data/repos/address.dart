// Address model — a delivery target row from public.addresses (labels
// home / work / other per migration 0001). Checkout (#003) reads the same
// table; this file stays schema-only with no code coupling to checkout.
enum AddressLabel { home, work, other }

extension AddressLabelX on AddressLabel {
  String get key => switch (this) {
        AddressLabel.home => 'home',
        AddressLabel.work => 'work',
        AddressLabel.other => 'other',
      };

  static AddressLabel fromKey(String key) => switch (key) {
        'home' => AddressLabel.home,
        'work' => AddressLabel.work,
        _ => AddressLabel.other,
      };
}

class AddressRecord {
  const AddressRecord({
    required this.id,
    required this.phone,
    required this.label,
    required this.addressText,
  });

  final String id;
  final String phone;
  final AddressLabel label;
  final String addressText;

  static AddressRecord fromRow(Map<String, dynamic> row) => AddressRecord(
        id: row['id'] as String,
        phone: row['phone'] as String,
        label: AddressLabelX.fromKey(row['label'] as String? ?? 'other'),
        addressText: row['address_text'] as String? ?? '',
      );
}
