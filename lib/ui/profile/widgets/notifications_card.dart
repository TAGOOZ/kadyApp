// Notifications preferences (#011): 4 switches persisted locally in
// SharedPreferences under `notifications.*` — no push in MVP (§11.22).
// Content-only: the screen supplies the card chrome and section title.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/strings_profile.dart';
import '../../../core/theme/app_theme.dart';

const _notifOrdersKey = 'notifications.orders';
const _notifOffersKey = 'notifications.offers';
const _notifMatchesKey = 'notifications.matches';
const _notifExamsKey = 'notifications.exams';

class NotificationsCard extends ConsumerStatefulWidget {
  const NotificationsCard({super.key, required this.strings});

  final ProfileStrings strings;

  @override
  ConsumerState<NotificationsCard> createState() =>
      _NotificationsCardState();
}

class _NotificationsCardState extends ConsumerState<NotificationsCard> {
  static const _defaults = {
    _notifOrdersKey: true,
    _notifOffersKey: true,
    _notifMatchesKey: true,
    _notifExamsKey: true,
  };

  final Map<String, bool> _values = Map.of(_defaults);

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final key in _defaults.keys) {
        _values[key] = prefs.getBool(key) ?? _defaults[key]!;
      }
    });
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _values[key] = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Column(
      children: [
        _NotifTile(
          label: s.notifOrders,
          value: _values[_notifOrdersKey]!,
          switchKey: const Key('profile_notif_orders'),
          onChanged: (v) => _toggle(_notifOrdersKey, v),
        ),
        const Divider(),
        _NotifTile(
          label: s.notifOffers,
          value: _values[_notifOffersKey]!,
          switchKey: const Key('profile_notif_offers'),
          onChanged: (v) => _toggle(_notifOffersKey, v),
        ),
        const Divider(),
        _NotifTile(
          label: s.notifMatchNights,
          value: _values[_notifMatchesKey]!,
          switchKey: const Key('profile_notif_matches'),
          onChanged: (v) => _toggle(_notifMatchesKey, v),
        ),
        const Divider(),
        _NotifTile(
          label: s.notifExams,
          value: _values[_notifExamsKey]!,
          switchKey: const Key('profile_notif_exams'),
          onChanged: (v) => _toggle(_notifExamsKey, v),
        ),
      ],
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({
    required this.label,
    required this.value,
    required this.switchKey,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final Key switchKey;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.bodyLg)),
        Switch(value: value, key: switchKey, onChanged: onChanged),
      ],
    );
  }
}
