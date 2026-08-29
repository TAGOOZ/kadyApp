// Hours editor panel — admin opening hours & delivery availability per day.
// Uses `public.hours` (supabase/migrations/0008_hours.sql). 7-row list
// with tappable open/close times (showTimePicker) + delivery toggle.
// Western digits (§11.11), RTL-first, optimistic with rollback.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/strings_admin.dart';
import '../../../core/l10n/strings_common.dart';
import '../../../data/repos/hours_repository.dart';
import '../../../core/theme/app_theme.dart';

class HoursEditorPanel extends ConsumerStatefulWidget {
  const HoursEditorPanel({super.key, required this.strings, required this.onAccessDenied});
  final AdminStrings strings;
  final VoidCallback onAccessDenied;
  @override
  ConsumerState<HoursEditorPanel> createState() => _HoursEditorPanelState();
}

class _HoursEditorPanelState extends ConsumerState<HoursEditorPanel> {
  List<Map<String, dynamic>>? _hours;
  bool _loading = true;

  static const _dayLabelsAr = ['السبت','الأحد','الإثنين','الثلاثاء','الأربعاء','الخميس','الجمعة'];
  static const _dayLabelsEn = ['Sat','Sun','Mon','Tue','Wed','Thu','Fri'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(hoursRepositoryProvider).fetchAll();
      if (!mounted) return;
      setState(() {
        _hours = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleDelivery(int day, bool enabled) async {
    final hours = _hours;
    if (hours == null) return;
    final idx = hours.indexWhere((r) => r['day'] == day);
    if (idx < 0) return;
    final prev = Map<String, dynamic>.from(hours[idx]);
    setState(() => _hours![idx] = {...prev, 'delivery_enabled': enabled});
    try {
      await ref.read(hoursRepositoryProvider).updateDay(day, {'delivery_enabled': enabled});
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(() => _hours![idx] = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.revertedError)));
    }
  }

  TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTime(TimeOfDay t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _editTime(int day, String column) async {
    final hours = _hours;
    if (hours == null) return;
    final idx = hours.indexWhere((r) => r['day'] == day);
    if (idx < 0) return;
    final current = _parseTime(hours[idx][column] as String?) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (picked == null) return;
    final newVal = _formatTime(picked);
    final prev = Map<String, dynamic>.from(hours[idx]);
    setState(() => _hours![idx] = {...prev, column: newVal});
    try {
      await ref.read(hoursRepositoryProvider).updateDay(day, {column: newVal});
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.saved)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _hours![idx] = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.revertedError)));
    }
  }

  Future<void> _toggleClosed(int day, bool closed) async {
    final hours = _hours;
    if (hours == null) return;
    final idx = hours.indexWhere((r) => r['day'] == day);
    if (idx < 0) return;
    final prev = Map<String, dynamic>.from(hours[idx]);
    final patch = closed ? {'open': null, 'close': null} : {'open': '09:00', 'close': '23:00'};
    setState(() => _hours![idx] = {...prev, ...patch});
    try {
      await ref.read(hoursRepositoryProvider).updateDay(day, patch);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.saved)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _hours![idx] = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.revertedError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeNotifierProvider);
    final isAr = lang == AppLang.ar;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final hours = _hours ?? const [];
    if (hours.isEmpty) return Center(child: Text(widget.strings.noData));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.sm16),
        itemCount: hours.length,
        itemBuilder: (context, index) {
          final row = hours[index];
          final day = row['day'] as int;
          final open = row['open'] as String?;
          final close = row['close'] as String?;
          final delivery = row['delivery_enabled'] as bool? ?? true;
          final closed = open == null || close == null;
          final label = isAr ? _dayLabelsAr[day % 7] : _dayLabelsEn[day % 7];
          final timeLabel = closed ? (isAr ? 'مغلق' : 'Closed') : '$open - $close';
          return Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                children: [
                  ListTile(
                    title: Text(label, style: AppTextStyles.labelMd.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: InkWell(
                      onTap: closed ? null : () => _editTime(day, 'open'),
                      borderRadius: BorderRadius.circular(AppRadii.md8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(closed ? Icons.block_outlined : Icons.access_time, size: 16, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text(timeLabel, style: AppTextStyles.bodySm.copyWith(color: closed ? AppColors.textMuted : AppColors.coffeeBean)),
                            if (!closed) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _editTime(day, 'close'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(AppRadii.pill),
                                  ),
                                  child: Text(close, style: AppTextStyles.labelMd.copyWith(color: AppColors.primary)),
                                ),
                              ),
                            ],
                            const Spacer(),
                            TextButton(
                              onPressed: () => _toggleClosed(day, !closed),
                              child: Text(closed
                                  ? CommonStrings.of(lang).open
                                  : CommonStrings.of(lang).close),
                            ),
                          ],
                        ),
                      ),
                    ),
                    trailing: Tooltip(
                      message: closed ? (isAr ? 'متاح فقط عند الفتح' : 'Available only when open') : (isAr ? 'توصيل' : 'Delivery'),
                      child: Switch(
                        value: delivery,
                        onChanged: closed ? null : (v) => _toggleDelivery(day, v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
